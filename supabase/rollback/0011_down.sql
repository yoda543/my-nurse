-- Retour arrière de 0011_operations.sql. À exécuter dans une transaction
-- (begin … commit), après 0011 et avant de revenir sur 0010.
-- Données perdues : tables platform_settings, availability_rules,
-- availability_exceptions, payments, subscriptions, pharmacies, complaints ;
-- colonnes ajoutées à contracts, withdrawals, reviews, notifications.
-- Les commissions déjà figées sur les réservations ne changent pas.

-- Garde-fou : ne s'exécute que si on le confirme explicitement dans la session :
--   set mynurse.confirm_rollback = 'yes';
-- AVANT : exporter les tables listées ci-dessous (pg_dump --data-only -t …).
do $$
begin
  if current_setting('mynurse.confirm_rollback', true) is distinct from 'yes' then
    raise exception 'Retour arrière non confirmé (set mynurse.confirm_rollback = yes).';
  end if;
end $$;

-- Fonctions remises dans leur version précédente (0004, 0007, 0008).
CREATE OR REPLACE FUNCTION private.price_booking()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_price int;
  v_hour int;
  v_night_ok boolean;
  v_needs_rx boolean;
  v_duration int;
  v_first public.bookings;
begin
  select ps.price, p.night_available, s.needs_prescription, s.duration_minutes
    into v_price, v_night_ok, v_needs_rx, v_duration
  from public.pro_services ps
  join public.pros p on p.id = ps.pro_id
  join public.services s on s.id = ps.service_id
  where ps.pro_id = new.pro_id and ps.service_id = new.service_id
    and p.verification_status = 'verified' and s.active
    and new.commune = any (p.communes);
  if v_price is null then
    raise exception 'Ce soignant ne propose pas ce soin dans cette commune.';
  end if;
  if new.scheduled_at < now() + interval '1 hour' then
    raise exception 'Réservez au moins 1 h à l''avance, le temps que le soignant se déplace.';
  end if;
  if new.scheduled_at > now() + interval '60 days' then
    raise exception 'On ne réserve pas plus de 60 jours à l''avance.';
  end if;
  if v_needs_rx and not new.has_prescription then
    raise exception 'Ce soin se fait uniquement sur ordonnance.';
  end if;
  v_hour := extract(hour from new.scheduled_at at time zone 'Africa/Abidjan');
  new.night := v_hour >= 21 or v_hour < 6;
  if new.night and not v_night_ok then
    raise exception 'Ce soignant ne fait pas de soins de nuit.';
  end if;
  new.slot := tstzrange(new.scheduled_at, new.scheduled_at + make_interval(mins => v_duration));
  if exists (
    select 1 from public.bookings b
    where b.pro_id = new.pro_id and b.status = 'accepted' and b.slot && new.slot
  ) then
    raise exception 'Ce soignant a déjà un soin à cette heure. Choisissez un autre créneau.';
  end if;
  -- Suivi régulier : même patient, même soignant, même soin.
  if new.contract_id is not null then
    if not exists (select 1 from public.contracts c
                   where c.id = new.contract_id and c.booked_by = new.booked_by) then
      raise exception 'Suivi introuvable.';
    end if;
    select * into v_first from public.bookings
      where contract_id = new.contract_id order by session_index limit 1;
    if found and (v_first.pro_id, v_first.service_id, v_first.patient_id)
                 is distinct from (new.pro_id, new.service_id, new.patient_id) then
      raise exception 'Toutes les séances d''un suivi concernent le même soin et le même soignant.';
    end if;
    if (select count(*) from public.bookings where contract_id = new.contract_id) >= 30 then
      raise exception 'Un suivi compte au plus 30 séances.';
    end if;
  end if;
  -- Commission unique de 10 %, soin ponctuel comme suivi régulier.
  new.commission_rate := 0.10;
  new.base_price := v_price;
  new.price := case when new.night then round(v_price * 1.5) else v_price end;
  new.commission := round(new.price * new.commission_rate);
  new.status := 'pending';
  new.created_at := now();
  return new;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.subscribe_premium()
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_until timestamptz;
begin
  if not exists (select 1 from public.pros where id = (select auth.uid()) and verification_status = 'verified') then
    raise exception 'Réservé aux soignants vérifiés.';
  end if;
  perform private.wallet_move((select auth.uid()), 'subscription', -5000, null, null, 'Abonnement Pro Premium (30 jours)');
  update public.pros
    set premium_until = greatest(coalesce(premium_until, now()), now()) + interval '30 days'
    where id = (select auth.uid())
    returning premium_until into v_until;
  return v_until;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.admin_verify_pro(p_pro uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_type public.pro_type;
  v_referrer uuid;
  v_rewarded boolean;
begin
  perform private.require_admin();
  select pro_type, referred_by, referral_rewarded into v_type, v_referrer, v_rewarded
    from public.pros where id = p_pro and verification_status in ('pending', 'suspended');
  if v_type is null then
    raise exception 'Ce dossier n''est pas à valider.';
  end if;
  if exists (
    select unnest(private.required_docs(v_type))
    except select doc_type from public.pro_documents where pro_id = p_pro
  ) then
    raise exception 'Dossier incomplet.';
  end if;
  update public.pros set verification_status = 'verified', rejection_reason = '',
      referral_rewarded = referral_rewarded or v_referrer is not null
    where id = p_pro;
  if v_referrer is not null and not v_rewarded then
    update public.pros
      set premium_until = greatest(coalesce(premium_until, now()), now()) + interval '30 days'
      where id = v_referrer;
  end if;
end;
$function$
;

CREATE OR REPLACE FUNCTION private.on_wallet_tx_notify()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

drop trigger if exists pro_services_price_range on public.pro_services;
drop trigger if exists bookings_price_zz_availability on public.bookings;
drop trigger if exists bookings_contract_fill on public.bookings;
drop trigger if exists reviews_moderation_audit on public.reviews;
drop trigger if exists pro_services_audit on public.pro_services;

drop policy if exists reviews_select on public.reviews;
create policy reviews_select on public.reviews as PERMISSIVE for SELECT to authenticated
  using (true);

drop function if exists public.admin_update_setting(text, jsonb);
drop function if exists public.admin_commission_report(date, date);
drop function if exists public.admin_settle_withdrawal(uuid, boolean, text, text);
drop function if exists public.admin_hide_review(uuid, boolean, text);
drop function if exists public.open_complaint(uuid, public.complaint_category, text);
drop function if exists public.admin_update_complaint(uuid, public.complaint_status, text, int, uuid);
drop function if exists private.check_pro_service_price();
drop function if exists private.check_availability();
drop function if exists private.contract_fill();

drop table if exists public.complaints, public.pharmacies, public.subscriptions, public.payments,
  public.availability_exceptions, public.availability_rules, public.platform_settings;
drop function if exists private.setting_num(text, numeric);
drop type if exists public.complaint_status, public.complaint_category, public.payment_status;

drop index if exists public.bookings_service_idx, public.bookings_open_idx, public.pro_cancellations_booking_idx,
  public.wallet_transactions_booking_fk_idx, public.pros_referred_by_idx, public.care_logs_booking_pro_idx,
  public.notifications_unread_idx, public.withdrawals_status_idx, public.contracts_booked_by_idx;

alter table public.notifications drop column if exists kind;
alter table public.reviews drop column if exists hidden_at, drop column if exists hidden_by,
  drop column if exists hidden_reason;
alter table public.withdrawals drop column if exists processed_at, drop column if exists processed_by,
  drop column if exists failure_reason;
alter table public.contracts drop column if exists patient_id, drop column if exists pro_id,
  drop column if exists service_id, drop column if exists status, drop column if exists sessions_planned;

-- La note moyenne des soignants est recalculée sur tous les avis
-- (les avis masqués redeviennent visibles).
update public.pros p set rating_count = s.n, rating_avg = coalesce(s.avg, 0)
from (select pro_id, count(*)::int n, round(avg(rating)::numeric, 2) avg from public.reviews group by pro_id) s
where p.id = s.pro_id;
