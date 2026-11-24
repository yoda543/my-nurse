-- Notifications (la cloche de l'app), créées par le serveur à chaque étape.

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles on delete cascade,
  title text not null,
  body text not null default '',
  booking_id uuid references public.bookings on delete cascade,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
create index notifications_user_idx on public.notifications (user_id, created_at desc);
create index notifications_booking_idx on public.notifications (booking_id);

alter table public.notifications enable row level security;
revoke all on public.notifications from anon, authenticated;
grant select on public.notifications to authenticated;
grant update (read_at) on public.notifications to authenticated;
create policy notifications_select on public.notifications for select to authenticated
  using (user_id = (select auth.uid()));
create policy notifications_update on public.notifications for update to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- ------------------------------------------------------------- outils
create function private.notify(p_user uuid, p_title text, p_body text, p_booking uuid default null)
returns void language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, title, body, booking_id)
  select p_user, p_title, p_body, p_booking where p_user is not null;
$$;

create function private.notify_admins(p_title text, p_body text) returns void
language sql security definer set search_path = '' as $$
  insert into public.notifications (user_id, title, body)
  select id, p_title, p_body from public.profiles where role = 'admin';
$$;

create function private.fcfa(p int) returns text
language sql immutable set search_path = '' as $$
  select replace(to_char(p, 'FM999,999,999'), ',', ' ') || ' FCFA';
$$;

create function private.when_label(p timestamptz) returns text
language sql immutable set search_path = '' as $$
  select to_char(p at time zone 'Africa/Abidjan', 'DD/MM à HH24"h"MI');
$$;

create function private.patient_name(p uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select full_name from public.patients where id = p), 'Le patient');
$$;

create function private.pro_name(p uuid) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select display_name from public.pros where id = p), 'Le soignant');
$$;

create function private.service_name(p text) returns text
language sql stable security definer set search_path = '' as $$
  select coalesce((select name from public.services where id = p), 'Soin');
$$;

-- Pour un suivi, une seule notification : la séance de plus petit rang parmi
-- celles que l'action vient de changer (les déclencheurs AFTER voient l'état
-- final de l'instruction).
create function private.first_of_group(b public.bookings, p_status public.booking_status)
returns boolean language sql stable security definer set search_path = '' as $$
  select b.contract_id is null or b.session_index = (
    select min(session_index) from public.bookings
    where contract_id = b.contract_id and status = p_status
      and cancel_reason is not distinct from b.cancel_reason
  );
$$;

-- ------------------------------------------------------------- soins
create function private.on_booking_insert_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.contract_id is null then
    perform private.notify(new.pro_id, 'Nouvelle demande de soin',
      private.service_name(new.service_id) || ' pour ' || private.patient_name(new.patient_id)
        || ', le ' || private.when_label(new.scheduled_at) || '. Répondez avant '
        || to_char(least(new.created_at + interval '2 hours', new.scheduled_at) at time zone 'Africa/Abidjan', 'HH24"h"MI') || '.',
      new.id);
  elsif new.session_index = 0 then
    perform private.notify(new.pro_id, 'Nouveau suivi demandé',
      private.service_name(new.service_id) || ' pour ' || private.patient_name(new.patient_id)
        || ', à partir du ' || private.when_label(new.scheduled_at) || '.',
      new.id);
  end if;
  return null;
end;
$$;
create trigger bookings_notify_insert after insert on public.bookings
  for each row execute function private.on_booking_insert_notify();

create function private.on_booking_update_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_service text := private.service_name(new.service_id);
  v_patient text := private.patient_name(new.patient_id);
  v_pro text := private.pro_name(new.pro_id);
begin
  -- Réponse du soignant.
  if old.status = 'pending' and new.status = 'accepted' and private.first_of_group(new, 'accepted') then
    perform private.notify(new.booked_by, v_pro || ' a confirmé votre soin',
      'Payez avant ' || to_char(least(new.accepted_at + interval '2 hours', new.scheduled_at) at time zone 'Africa/Abidjan', 'HH24"h"MI')
        || ' pour valider le rendez-vous.', new.id);
  elsif old.status = 'pending' and new.status = 'refused' and private.first_of_group(new, 'refused') then
    perform private.notify(new.booked_by, v_pro || ' n’est pas disponible',
      'Choisissez un autre soignant pour ' || v_service || '.', new.id);
  end if;

  -- Paiement.
  if old.paid_at is null and new.paid_at is not null and (new.contract_id is null or new.session_index = (
       select min(session_index) from public.bookings where contract_id = new.contract_id and status = 'accepted')) then
    perform private.notify(new.pro_id, 'Paiement reçu',
      v_patient || ' a payé ' || v_service || '. Vous pouvez vous déplacer le '
        || private.when_label(new.scheduled_at) || '.', new.id);
  end if;

  -- Annulations.
  if old.status <> 'cancelled' and new.status = 'cancelled' and private.first_of_group(new, 'cancelled') then
    if new.cancel_reason like 'Annulé par le soignant%' then
      perform private.notify(new.booked_by, 'Soin annulé par le soignant',
        v_pro || ' : ' || substr(new.cancel_reason, length('Annulé par le soignant : ') + 1) || '. '
          || case when new.paid_at is not null then 'Vous êtes remboursé sur votre solde MyNurse. ' else '' end
          || 'Choisissez un autre soignant.', new.id);
    elsif new.cancel_reason like 'Annulé par le patient%' then
      perform private.notify(new.pro_id, 'Soin annulé par le patient',
        v_patient || ' a annulé ' || v_service || ' du ' || private.when_label(new.scheduled_at) || '.'
          || case when new.cancellation_fee > 0
               then ' Dédommagement de ' || private.fcfa(new.cancellation_fee - round(new.cancellation_fee * new.commission_rate)::int) || ' versé sur votre solde.'
               else '' end, new.id);
    elsif new.cancel_reason like 'Sans réponse%' then
      perform private.notify(new.booked_by, 'Demande sans réponse',
        v_pro || ' n’a pas répondu à temps. Choisissez un autre soignant pour ' || v_service || '.', new.id);
      perform private.notify(new.pro_id, 'Demande expirée',
        v_service || ' pour ' || v_patient || ' : délai de réponse dépassé.', new.id);
    elsif new.cancel_reason like 'Non payé%' then
      perform private.notify(new.booked_by, 'Rendez-vous annulé',
        v_service || ' avec ' || v_pro || ' n’a pas été payé à temps.', new.id);
      perform private.notify(new.pro_id, 'Rendez-vous annulé',
        v_patient || ' n’a pas payé à temps : ne vous déplacez pas.', new.id);
    elsif new.cancel_reason like 'Soignant suspendu%' then
      perform private.notify(new.booked_by, 'Soin annulé',
        v_pro || ' n’est plus disponible sur MyNurse. '
          || case when new.paid_at is not null then 'Vous êtes remboursé sur votre solde. ' else '' end
          || 'Choisissez un autre soignant.', new.id);
    end if;
  end if;

  -- Fin du soin.
  if old.status <> 'done' and new.status = 'done' then
    perform private.notify(new.booked_by, 'Compte rendu disponible',
      v_pro || ' a terminé ' || v_service || ' pour ' || v_patient || '. Pensez à noter le soin.', new.id);
    perform private.notify(new.pro_id, 'Paiement versé',
      private.fcfa(new.price - new.commission) || ' ajoutés à votre solde pour ' || v_service || '.', new.id);
  end if;
  return null;
end;
$$;
create trigger bookings_notify_update after update of status, paid_at on public.bookings
  for each row execute function private.on_booking_update_notify();

create function private.on_review_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  perform private.notify(new.pro_id, 'Nouvelle note : ' || new.rating || '/5',
    case when new.comment = '' then 'Merci pour votre soin.' else '« ' || new.comment || ' »' end,
    new.booking_id);
  return null;
end;
$$;
create trigger reviews_notify after insert on public.reviews
  for each row execute function private.on_review_notify();

-- ------------------------------------------------------------- soignants
create function private.on_pro_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if tg_op = 'INSERT' then
    perform private.notify_admins('Nouveau dossier à vérifier',
      new.display_name || ' · ' || array_to_string(new.communes, ', ') || '.');
    return null;
  end if;
  if new.verification_status is distinct from old.verification_status then
    if new.verification_status = 'verified' then
      perform private.notify(new.id, 'Votre compte est vérifié',
        'Vous apparaissez dans les recherches des patients de vos communes.');
      if new.referred_by is not null and new.referral_rewarded and not old.referral_rewarded then
        perform private.notify(new.referred_by, 'Parrainage : 30 jours de Premium offerts',
          new.display_name || ' est maintenant vérifié(e). Merci de faire connaître MyNurse.');
      end if;
    elsif new.verification_status = 'rejected' then
      perform private.notify(new.id, 'Dossier à compléter', new.rejection_reason);
    elsif new.verification_status = 'suspended' then
      perform private.notify(new.id, 'Compte suspendu', new.rejection_reason);
    elsif new.verification_status = 'pending' and old.verification_status = 'rejected' then
      perform private.notify_admins('Dossier renvoyé', new.display_name || ' a complété son dossier.');
    end if;
  end if;
  return null;
end;
$$;
create trigger pros_notify after insert or update of verification_status on public.pros
  for each row execute function private.on_pro_notify();

create function private.on_pro_cancellation_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if (select count(*) from public.pro_cancellations
      where pro_id = new.pro_id and created_at > now() - interval '30 days') = 2 then
    perform private.notify_admins('Alerte fiabilité',
      private.pro_name(new.pro_id) || ' a annulé 2 soins confirmés en 30 jours.');
  end if;
  return null;
end;
$$;
create trigger pro_cancellations_notify after insert on public.pro_cancellations
  for each row execute function private.on_pro_cancellation_notify();

-- ------------------------------------------------------------- soldes
create function private.on_wallet_tx_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.kind = 'topup' then
    perform private.notify(new.owner_id, 'Recharge confirmée',
      private.fcfa(new.amount) || ' ajoutés à votre solde.');
  elsif new.kind = 'withdrawal' then
    perform private.notify(new.owner_id, 'Retrait demandé',
      private.fcfa(-new.amount) || ' vers votre compte Mobile Money.');
  elsif new.kind = 'subscription' then
    perform private.notify(new.owner_id, 'Pro Premium activé',
      'Vous êtes mis en avant pendant 30 jours.');
  elsif new.kind = 'refund' and new.booking_id is null then
    perform private.notify(new.owner_id, 'Paiement crédité sur votre solde',
      private.fcfa(new.amount) || ' reçus après l’expiration du rendez-vous.');
  end if;
  return null;
end;
$$;
create trigger wallet_transactions_notify after insert on public.wallet_transactions
  for each row execute function private.on_wallet_tx_notify();

-- Bienvenue au nouveau patient (quand il donne son nom).
create function private.on_profile_name_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.full_name = '' and new.full_name <> '' and new.role = 'patient' then
    perform private.notify(new.id, 'Bienvenue sur MyNurse',
      'Rechargez votre solde, puis réservez un soignant vérifié près de chez vous.');
  end if;
  return null;
end;
$$;
create trigger profiles_notify_name after update of full_name on public.profiles
  for each row execute function private.on_profile_name_notify();
