-- 0013 · Console d'administration : indicateurs sans données nominatives,
-- actions de l'équipe (annulation, remboursement, abonnement, message,
-- incidents), toutes soumises à une permission précise et journalisées.
-- L'équipe n'a toujours aucun accès direct aux dossiers médicaux
-- (seulement admin_break_glass, 0009).
--
-- Additive.

-- Gestes de remboursement de l'équipe, en plus de celui d'une annulation.
alter table public.bookings add column if not exists admin_refunded int not null default 0
  check (admin_refunded >= 0);

-- ======================================================== contexte console
-- Permissions du membre connecté et comptages agrégés (aucun nom, aucune
-- donnée de santé). L'équipe ne lit pas la table patients directement.
create function public.admin_dashboard_context() returns jsonb
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.is_admin() then
    raise exception 'Réservé à l''équipe MyNurse.';
  end if;
  return jsonb_build_object(
    'permissions', (select coalesce(jsonb_agg(permission order by permission), '[]')
                    from public.staff_permissions where profile_id = (select auth.uid())),
    'patients', (select count(*) from public.patients),
    'accounts', (select count(*) from public.profiles where role = 'patient')
  );
end;
$$;

-- ===================================================== rendez-vous
-- Annulation par l'équipe : remboursement intégral, famille et soignant
-- prévenus.
create function public.admin_cancel_booking(p_booking uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  b public.bookings;
  v_id uuid;
begin
  perform private.require_perm('manage_bookings');
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Indiquez le motif (vu par la famille).';
  end if;
  select * into b from public.bookings where id = p_booking and status in ('pending', 'accepted');
  if b.id is null then
    raise exception 'Ce rendez-vous n''est plus en cours.';
  end if;
  for v_id in
    update public.bookings
      set status = 'cancelled', cancel_reason = 'Annulé par MyNurse : ' || trim(p_reason)
      where (id = p_booking or (b.contract_id is not null and contract_id = b.contract_id))
        and status in ('pending', 'accepted')
      returning id
  loop
    perform private.refund_booking(v_id, 0);
  end loop;
  perform private.notify(b.booked_by, 'Soin annulé par MyNurse', trim(p_reason), p_booking);
  perform private.notify(b.pro_id, 'Soin annulé par MyNurse', trim(p_reason), p_booking);
  perform audit.log('admin_cancel', 'bookings', p_booking::text, null, trim(p_reason));
end;
$$;

-- Remboursement (geste ou litige) sur le solde de la famille, plafonné à
-- ce qui reste payé et non remboursé.
create function public.admin_refund_booking(p_booking uuid, p_amount int, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  b public.bookings;
  v_already int;
begin
  perform private.require_perm('finance');
  if length(trim(coalesce(p_reason, ''))) < 5 then
    raise exception 'Indiquez le motif du remboursement.';
  end if;
  select * into b from public.bookings where id = p_booking for update;
  if b.id is null or b.paid_at is null then
    raise exception 'Ce soin n''a pas été payé.';
  end if;
  v_already := b.admin_refunded
    + case when b.refunded then b.price - b.cancellation_fee else 0 end;
  if p_amount <= 0 or p_amount > b.price - v_already then
    raise exception 'Montant entre 1 et % FCFA.', b.price - v_already;
  end if;
  update public.bookings set admin_refunded = admin_refunded + p_amount where id = p_booking;
  perform private.wallet_move(b.booked_by, 'refund', p_amount, null,
    'admin-refund-' || p_booking::text || '-' || (b.admin_refunded + p_amount)::text,
    'Remboursement MyNurse');
  perform private.notify(b.booked_by, 'Remboursement',
    p_amount || ' FCFA crédités sur votre solde : ' || trim(p_reason), p_booking);
  perform audit.log('admin_refund', 'bookings', p_booking::text, null, trim(p_reason),
    jsonb_build_object('amount', p_amount));
end;
$$;

-- ===================================================== abonnements
create function public.admin_extend_premium(p_pro uuid, p_days int, p_reason text) returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  v_start timestamptz;
  v_until timestamptz;
begin
  perform private.require_perm('finance');
  if p_days not between 1 and 365 then
    raise exception 'Entre 1 et 365 jours.';
  end if;
  select greatest(coalesce(premium_until, now()), now()) into v_start from public.pros where id = p_pro;
  if v_start is null then
    raise exception 'Soignant introuvable.';
  end if;
  update public.pros set premium_until = v_start + make_interval(days => p_days)
    where id = p_pro returning premium_until into v_until;
  insert into public.subscriptions (pro_id, source, starts_at, ends_at)
    values (p_pro, 'admin', v_start, v_until);
  perform private.notify(p_pro, 'Pro Premium offert', p_days || ' jours offerts par MyNurse.');
  perform audit.log('admin_premium', 'pros', p_pro::text, null, p_reason);
  return v_until;
end;
$$;

-- ======================================================== messages
-- Message collectif. Renvoie le nombre de destinataires.
create function public.admin_broadcast(p_audience text, p_title text, p_body text) returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_count int;
begin
  perform private.require_perm('manage_settings');
  if p_audience not in ('all', 'patients', 'pros') then
    raise exception 'Destinataires inconnus.';
  end if;
  if length(trim(coalesce(p_title, ''))) < 3 or length(trim(coalesce(p_body, ''))) < 5 then
    raise exception 'Titre et message obligatoires.';
  end if;
  insert into public.notifications (user_id, title, body)
  select p.id, left(trim(p_title), 120), left(trim(p_body), 1000)
  from public.profiles p
  where (p_audience in ('all', 'patients') and p.role = 'patient')
     or (p_audience in ('all', 'pros') and p.role = 'pro' and private.pro_is_active(p.id));
  get diagnostics v_count = row_count;
  perform audit.log('admin_broadcast', 'notifications', null, null, p_audience,
    jsonb_build_object('title', trim(p_title), 'recipients', v_count));
  return v_count;
end;
$$;

-- ======================================================== incidents
create function public.admin_update_incident(p_id uuid, p_status text, p_note text default '')
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_reporter uuid;
begin
  perform private.require_perm('support');
  if p_status not in ('open', 'in_review', 'closed') then
    raise exception 'Statut inconnu.';
  end if;
  if p_status = 'closed' and length(trim(coalesce(p_note, ''))) < 5 then
    raise exception 'Indiquez ce qui a été fait.';
  end if;
  update public.incident_reports
    set status = p_status, resolution = coalesce(nullif(trim(p_note), ''), resolution),
        handled_by = (select auth.uid()), updated_at = now()
    where id = p_id
    returning reporter_id into v_reporter;
  if v_reporter is null then
    raise exception 'Incident introuvable.';
  end if;
  perform private.notify(v_reporter,
    case p_status when 'closed' then 'Incident traité' else 'Incident pris en charge' end,
    coalesce(nullif(trim(p_note), ''), 'L''équipe MyNurse s''en occupe.'));
end;
$$;

-- L'équipe support lit les incidents (déjà prévu en 0012) ; les mises à
-- jour passent uniquement par la fonction ci-dessus.

-- ====================================== recherche : pas de priorité Premium
-- Le classement suit la note (pondérée par le nombre d'avis), pas
-- l'abonnement. « featured » reste renvoyé pour un éventuel badge.
-- Sinon identique à 0012.
create or replace function public.search_pros(p_service text, p_commune text)
returns table (id uuid, display_name text, pro_type public.pro_type, price int,
               rating_avg numeric, rating_count int, care_count int, featured boolean)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.display_name, p.pro_type, ps.price, p.rating_avg, p.rating_count, p.care_count,
         coalesce(p.premium_until > now(), false) as featured
  from public.pros p
  join public.pro_services ps on ps.pro_id = p.id and ps.service_id = p_service
  where p.verification_status = 'verified' and p_commune = any (p.communes)
    and private.pro_docs_ok(p.id)
  order by (p.rating_avg * p.rating_count + 4.0 * 5) / (p.rating_count + 5) desc, ps.price;
$$;

-- ========================================================= droits
revoke execute on function
  public.admin_dashboard_context(), public.admin_cancel_booking(uuid, text),
  public.admin_refund_booking(uuid, int, text), public.admin_extend_premium(uuid, int, text),
  public.admin_broadcast(text, text, text), public.admin_update_incident(uuid, text, text)
from public, anon;
grant execute on function
  public.admin_dashboard_context(), public.admin_cancel_booking(uuid, text),
  public.admin_refund_booking(uuid, int, text), public.admin_extend_premium(uuid, int, text),
  public.admin_broadcast(text, text, text), public.admin_update_incident(uuid, text, text)
to authenticated;
