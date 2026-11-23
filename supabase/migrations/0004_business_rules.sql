-- Règles métier : délais, créneaux, annulation, suivis réguliers,
-- Pro Premium, parrainage, reçus. Mêmes valeurs que lib/rules.dart.

create extension if not exists btree_gist with schema extensions;

alter type public.wallet_tx_kind add value if not exists 'subscription';

-- ------------------------------------------------------------------ données
alter table public.services
  add column duration_minutes int not null default 60
  check (duration_minutes between 15 and 720);
update public.services set duration_minutes = case id
  when 'injection' then 30 when 'perfusion' then 120 when 'pansement' then 45
  when 'sonde' then 45 when 'consultation' then 45 else 60 end;

create table public.contracts (
  id uuid primary key default gen_random_uuid(),
  booked_by uuid not null references public.profiles,
  frequency text not null check (frequency in ('daily', 'every_other_day', 'weekly')),
  created_at timestamptz not null default now()
);

alter table public.bookings
  add column accepted_at timestamptz,
  add column commission_rate numeric(4, 2) not null default 0.15,
  add column contract_id uuid references public.contracts on delete cascade,
  add column session_index int not null default 0,
  add column cancellation_fee int not null default 0,
  add column receipt_number text unique,
  add column slot tstzrange;
create index bookings_contract_idx on public.bookings (contract_id);

-- Un soignant ne peut pas avoir deux soins confirmés qui se chevauchent.
alter table public.bookings add constraint bookings_no_overlap
  exclude using gist (pro_id with =, slot with &&) where (status = 'accepted');

alter table public.pros
  add column premium_until timestamptz,
  add column referred_by uuid references public.pros,
  add column referral_rewarded boolean not null default false;

create table public.pro_cancellations (
  id uuid primary key default gen_random_uuid(),
  pro_id uuid not null references public.pros on delete cascade,
  booking_id uuid not null references public.bookings,
  reason text not null,
  created_at timestamptz not null default now()
);
create index pro_cancellations_pro_idx on public.pro_cancellations (pro_id, created_at desc);

create sequence public.receipt_seq;

-- ----------------------------------------------------------- règles pures
create function private.response_deadline(b public.bookings) returns timestamptz
language sql immutable set search_path = '' as $$
  select least(b.created_at + interval '2 hours', b.scheduled_at);
$$;

create function private.payment_deadline(b public.bookings) returns timestamptz
language sql immutable set search_path = '' as $$
  select least(b.accepted_at + interval '2 hours', b.scheduled_at);
$$;

-- 50 % retenus si l'annulation a lieu moins de 2 h avant le soin.
create function private.late_fee(b public.bookings) returns int
language sql stable set search_path = '' as $$
  select case
    when b.paid_at is null then 0
    when b.scheduled_at - now() >= interval '2 hours' then 0
    else round(b.price * 0.5)::int end;
$$;

-- --------------------------------------------------------- création d'un soin
-- Remplace le contrôle de 0001 : délais, créneau, commission, suivi.
create or replace function private.price_booking() returns trigger
language plpgsql security definer set search_path = '' as $$
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
  -- Suivi régulier : même patient, même soignant, même soin ; commission réduite.
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
    new.commission_rate := 0.10;
  else
    new.commission_rate := 0.15;
  end if;
  new.base_price := v_price;
  new.price := case when new.night then round(v_price * 1.5) else v_price end;
  new.commission := round(new.price * new.commission_rate);
  new.status := 'pending';
  new.created_at := now();
  return new;
end;
$$;

-- ----------------------------------------------------- réponse du soignant
create or replace function public.respond_booking(p_booking uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
declare
  b public.bookings;
  s public.bookings;
begin
  select * into b from public.bookings
    where id = p_booking and pro_id = (select auth.uid()) for update;
  if b.id is null or b.status <> 'pending' or now() >= private.response_deadline(b) then
    raise exception 'Cette demande a expiré ou a été traitée.';
  end if;
  -- Pour un suivi, la réponse vaut pour toutes les séances en attente.
  for s in
    select * from public.bookings
    where (id = b.id or (b.contract_id is not null and contract_id = b.contract_id))
      and status = 'pending'
    order by scheduled_at
    for update
  loop
    if p_accept and exists (
      select 1 from public.bookings o
      where o.pro_id = s.pro_id and o.status = 'accepted' and o.slot && s.slot
    ) then
      raise exception 'Vous avez déjà un soin le %. Refusez cette demande ou libérez ce créneau.',
        to_char(s.scheduled_at at time zone 'Africa/Abidjan', 'DD/MM à HH24"h"MI');
    end if;
    update public.bookings
      set status = case when p_accept then 'accepted' else 'refused' end::public.booking_status,
          accepted_at = case when p_accept then now() end
      where id = s.id;
  end loop;
end;
$$;

-- --------------------------------------------------------------- paiement
create function private.payable_group(p_booking uuid) returns setof public.bookings
language sql stable security definer set search_path = '' as $$
  select o.* from public.bookings b
  join public.bookings o on o.id = b.id or (b.contract_id is not null and o.contract_id = b.contract_id)
  where b.id = p_booking and o.status = 'accepted' and o.paid_at is null
    and now() < private.payment_deadline(o);
$$;

drop function public.pay_booking_with_wallet(uuid);
create function public.pay_booking_with_wallet(p_booking uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_total int;
  v_balance int;
begin
  if not exists (select 1 from public.bookings where id = p_booking and booked_by = (select auth.uid())) then
    raise exception 'Ce soin n''est pas à payer.';
  end if;
  perform 1 from public.bookings where id in (select id from private.payable_group(p_booking)) for update;
  select sum(price) into v_total from private.payable_group(p_booking);
  if v_total is null then
    raise exception 'Ce soin n''est pas à payer, ou le délai de paiement est dépassé.';
  end if;
  v_balance := private.wallet_move((select auth.uid()), 'payment', -v_total, p_booking, null, 'Paiement de soins');
  update public.bookings set paid_at = now(), payment_method = 'wallet'
    where id in (select id from private.payable_group(p_booking));
  return v_balance;
end;
$$;

-- Webhook Mobile Money. Si le rendez-vous n'est plus payable (délai dépassé,
-- annulé), l'argent reçu est crédité sur le solde du patient : rien ne se perd.
drop function public.confirm_payment(uuid, text, text);
create function public.confirm_payment(p_booking uuid, p_method text, p_ref text, p_amount int) returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_total int;
  v_owner uuid;
begin
  select booked_by into v_owner from public.bookings where id = p_booking;
  if v_owner is null then
    raise exception 'Réservation inconnue.';
  end if;
  select sum(price) into v_total from private.payable_group(p_booking);
  if v_total is not null and v_total = p_amount then
    update public.bookings set paid_at = now(), payment_method = p_method, payment_ref = p_ref
      where id in (select id from private.payable_group(p_booking));
    return 'paid';
  end if;
  perform private.wallet_move(v_owner, 'refund', p_amount, null, p_ref, 'Paiement reçu après expiration du rendez-vous');
  return 'credited_to_wallet';
end;
$$;

-- ------------------------------------------------------------- expirations
create function public.expire_stale_bookings() returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_count int;
begin
  with expired as (
    update public.bookings b
      set status = 'cancelled',
          cancel_reason = case when b.status = 'pending'
            then 'Sans réponse du soignant à temps' else 'Non payé à temps' end
      where (b.status = 'pending' and now() >= private.response_deadline(b))
         or (b.status = 'accepted' and b.paid_at is null and now() >= private.payment_deadline(b))
      returning 1
  )
  select count(*) into v_count from expired;
  return v_count;
end;
$$;

-- ------------------------------------------------------------- annulation
-- Rembourse un soin annulé ; une pénalité éventuelle revient au soignant,
-- commission déduite.
drop function private.refund_booking(uuid);
create function private.refund_booking(p_booking uuid, p_fee int default 0) returns void
language plpgsql security definer set search_path = '' as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings where id = p_booking;
  if b.paid_at is null then
    return;
  end if;
  update public.bookings set refunded = true, cancellation_fee = p_fee where id = p_booking;
  if b.price - p_fee > 0 then
    perform private.wallet_move(b.booked_by, 'refund', b.price - p_fee, p_booking, null, 'Remboursement d''un soin');
  end if;
  if p_fee > 0 then
    perform private.wallet_move(b.pro_id, 'earning', p_fee - round(p_fee * b.commission_rate)::int,
      p_booking, null, 'Annulation tardive');
  end if;
end;
$$;

create or replace function public.cancel_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  b public.bookings;
  s public.bookings;
  v_fee int;
begin
  select * into b from public.bookings where id = p_booking and booked_by = (select auth.uid());
  if b.id is null then
    raise exception 'Ce soin ne peut plus être annulé.';
  end if;
  for s in
    select * from public.bookings
    where (id = b.id or (b.contract_id is not null and contract_id = b.contract_id))
      and status in ('pending', 'accepted')
    for update
  loop
    v_fee := private.late_fee(s);
    update public.bookings
      set status = 'cancelled',
          cancel_reason = case when v_fee > 0
            then 'Annulé par le patient moins de 2 h avant le soin' else 'Annulé par le patient' end
      where id = s.id;
    perform private.refund_booking(s.id, v_fee);
  end loop;
  if not found then
    raise exception 'Ce soin ne peut plus être annulé.';
  end if;
end;
$$;

create function public.pro_cancel_booking(p_booking uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  b public.bookings;
  s public.bookings;
begin
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Indiquez le motif au patient.';
  end if;
  select * into b from public.bookings
    where id = p_booking and pro_id = (select auth.uid()) and status = 'accepted';
  if b.id is null then
    raise exception 'Seul un soin confirmé peut être annulé.';
  end if;
  for s in
    select * from public.bookings
    where (id = b.id or (b.contract_id is not null and contract_id = b.contract_id))
      and status in ('pending', 'accepted')
    for update
  loop
    update public.bookings set status = 'cancelled', cancel_reason = 'Annulé par le soignant : ' || p_reason
      where id = s.id;
    perform private.refund_booking(s.id, 0);
  end loop;
  insert into public.pro_cancellations (pro_id, booking_id, reason) values (b.pro_id, b.id, p_reason);
end;
$$;

-- La suspension rembourse en totalité (reprend 0003 avec la nouvelle signature).
create or replace function public.admin_suspend_pro(p_pro uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  perform private.require_admin();
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Indiquez un motif.';
  end if;
  update public.pros set verification_status = 'suspended', rejection_reason = p_reason
    where id = p_pro and verification_status = 'verified';
  if not found then
    raise exception 'Ce soignant n''est pas actif.';
  end if;
  for v_id in
    update public.bookings
      set status = 'cancelled', cancel_reason = 'Soignant suspendu par MyNurse'
      where pro_id = p_pro and status in ('pending', 'accepted')
      returning id
  loop
    perform private.refund_booking(v_id, 0);
  end loop;
end;
$$;

-- ------------------------------------------------------------- fin de soin
create or replace function private.on_care_log() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  b public.bookings;
begin
  select * into b from public.bookings
    where id = new.booking_id and pro_id = new.pro_id and status = 'accepted'
      and paid_at is not null
    for update;
  if b.id is null then
    raise exception 'Ce soin n''est pas confirmé, pas payé ou ne vous est pas attribué.';
  end if;
  if now() < b.scheduled_at - interval '30 minutes' then
    raise exception 'Le compte rendu s''écrit à partir de 30 minutes avant le soin.';
  end if;
  update public.bookings
    set status = 'done',
        receipt_number = 'MN-' || extract(year from now())::int || '-' || lpad(nextval('public.receipt_seq')::text, 5, '0')
    where id = b.id;
  update public.pros set care_count = care_count + 1 where id = new.pro_id;
  perform private.wallet_move(new.pro_id, 'earning', b.price - b.commission, new.booking_id, null, 'Soin terminé');
  return new;
end;
$$;

-- -------------------------------------------------- Pro Premium, parrainage
create function public.subscribe_premium() returns timestamptz
language plpgsql security definer set search_path = '' as $$
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
$$;

-- Le parrain doit être un soignant vérifié, différent du filleul.
create function private.check_referral() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.referred_by is not null and (new.referred_by = new.id or not exists (
    select 1 from public.pros where id = new.referred_by and verification_status = 'verified'
  )) then
    raise exception 'Code de parrainage inconnu.';
  end if;
  return new;
end;
$$;
create trigger pros_check_referral before insert on public.pros
  for each row execute function private.check_referral();

-- Validation : un mois Premium offert au parrain, une seule fois.
create or replace function public.admin_verify_pro(p_pro uuid) returns void
language plpgsql security definer set search_path = '' as $$
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
$$;

-- Recherche : soignants vérifiés, Pro Premium d'abord, puis les mieux notés.
create function public.search_pros(p_service text, p_commune text)
returns table (id uuid, display_name text, pro_type public.pro_type, price int,
               rating_avg numeric, rating_count int, care_count int, featured boolean)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.display_name, p.pro_type, ps.price, p.rating_avg, p.rating_count, p.care_count,
         coalesce(p.premium_until > now(), false) as featured
  from public.pros p
  join public.pro_services ps on ps.pro_id = p.id and ps.service_id = p_service
  where p.verification_status = 'verified' and p_commune = any (p.communes)
  order by featured desc, p.rating_avg desc;
$$;

-- Fiabilité : soignants avec au moins 2 annulations sur 30 jours.
create function public.admin_reliability_alerts()
returns table (pro_id uuid, display_name text, cancellations bigint)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_admin();
  return query
    select p.id, p.display_name, count(*)
    from public.pro_cancellations c join public.pros p on p.id = c.pro_id
    where c.created_at > now() - interval '30 days'
    group by p.id, p.display_name
    having count(*) >= 2;
end;
$$;

-- ------------------------------------------------------------------- droits
alter table public.contracts enable row level security;
alter table public.pro_cancellations enable row level security;
grant select, insert on public.contracts to authenticated;
grant select on public.pro_cancellations to authenticated;
grant insert (contract_id, session_index) on public.bookings to authenticated;
grant insert (referred_by) on public.pros to authenticated;

create policy contracts_insert on public.contracts for insert to authenticated
  with check (booked_by = (select auth.uid()));
create policy contracts_select on public.contracts for select to authenticated
  using (booked_by = (select auth.uid()) or (select private.is_admin())
    or exists (select 1 from public.bookings b where b.contract_id = contracts.id and b.pro_id = (select auth.uid())));
create policy pro_cancellations_select on public.pro_cancellations for select to authenticated
  using (pro_id = (select auth.uid()) or (select private.is_admin()));

revoke execute on function public.confirm_payment(uuid, text, text, int) from public, anon, authenticated;
revoke execute on function public.expire_stale_bookings() from public, anon, authenticated;
revoke execute on function public.pay_booking_with_wallet(uuid) from public, anon;
revoke execute on function public.pro_cancel_booking(uuid, text) from public, anon;
revoke execute on function public.subscribe_premium() from public, anon;
revoke execute on function public.admin_reliability_alerts() from public, anon;
grant execute on function public.pay_booking_with_wallet(uuid) to authenticated;
grant execute on function public.pro_cancel_booking(uuid, text) to authenticated;
grant execute on function public.subscribe_premium() to authenticated;
grant execute on function public.admin_reliability_alerts() to authenticated;
grant execute on function public.search_pros(text, text) to authenticated;

-- Vérification des délais chaque minute, si pg_cron est activé (Supabase :
-- Database > Extensions > pg_cron).
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_cron') then
    perform cron.schedule('expire-stale-bookings', '* * * * *', 'select public.expire_stale_bookings()');
  end if;
end;
$$;
