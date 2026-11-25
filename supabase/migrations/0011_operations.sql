-- 0011 · Exploitation : paramètres de la plateforme, contrôle des tarifs,
-- disponibilités, suivis réguliers enrichis, paiements, commissions,
-- retraits, abonnements, modération des avis, pharmacies, réclamations,
-- index manquants.
--
-- Additive : colonnes ajoutées nullables ou avec valeur par défaut,
-- aucune suppression.

-- =================================================== paramètres plateforme
-- Valeurs métier modifiables sans redéployer (non secrètes, lisibles par l'app).
create table public.platform_settings (
  key text primary key check (key ~ '^[a-z_]+$'),
  value jsonb not null,
  description text not null default '',
  updated_by uuid references public.profiles on delete set null,
  updated_at timestamptz not null default now()
);
insert into public.platform_settings (key, value, description) values
  ('commission_rate', '0.10', 'Commission MyNurse sur chaque soin (0,10 = 10 %)'),
  ('night_surcharge', '0.50', 'Majoration de nuit, 21 h - 6 h (0,50 = +50 %)'),
  ('premium_price', '5000', 'Prix de Pro Premium (FCFA)'),
  ('premium_days', '30', 'Durée de Pro Premium (jours)'),
  ('booking_grant_hours_after', '24', 'Accès au dossier après la fin prévue du soin (heures)')
on conflict (key) do nothing;

create function private.setting_num(p_key text, p_default numeric) returns numeric
language sql stable security definer set search_path = '' as $$
  select coalesce((select (value #>> '{}')::numeric from public.platform_settings where key = p_key), p_default);
$$;

create function public.admin_update_setting(p_key text, p_value jsonb) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_perm('manage_settings');
  if p_key = 'commission_rate' and ((p_value #>> '{}')::numeric not between 0 and 0.30) then
    raise exception 'Commission entre 0 et 30 %%.';
  end if;
  update public.platform_settings set value = p_value, updated_by = (select auth.uid()), updated_at = now()
    where key = p_key;
  if not found then
    raise exception 'Paramètre inconnu.';
  end if;
end;
$$;

-- ======================================================= prix des soins
-- Un soignant fixe son prix dans la fourchette du catalogue (contrôle serveur).
create function private.check_pro_service_price() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_min int;
  v_max int;
begin
  select min_price, max_price into v_min, v_max from public.services where id = new.service_id;
  if new.price < v_min or new.price > v_max then
    raise exception 'Prix hors fourchette : entre % et % FCFA.', v_min, v_max;
  end if;
  return new;
end;
$$;
create trigger pro_services_price_range before insert or update of price, service_id on public.pro_services
  for each row execute function private.check_pro_service_price();

-- Commission et majoration lues dans platform_settings (avant : codées en dur).
-- Le reste est identique à 0008_commission_10.sql.
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
  new.commission_rate := private.setting_num('commission_rate', 0.10);
  new.base_price := v_price;
  new.price := case when new.night
    then round(v_price * (1 + private.setting_num('night_surcharge', 0.50))) else v_price end;
  new.commission := round(new.price * new.commission_rate);
  new.status := 'pending';
  new.created_at := now();
  return new;
end;
$$;

-- ============================================================ disponibilités
-- Plages hebdomadaires (heure d'Abidjan) + exceptions (congé, plage en plus).
-- Tant qu'un soignant n'a déclaré aucune plage, il reste réservable comme
-- aujourd'hui : l'app actuelle continue de fonctionner.
create table public.availability_rules (
  id uuid primary key default gen_random_uuid(),
  pro_id uuid not null references public.pros on delete cascade,
  weekday smallint not null check (weekday between 1 and 7),   -- 1 = lundi (ISO)
  start_time time not null,
  end_time time not null,
  created_at timestamptz not null default now(),
  check (end_time > start_time)
);
create index availability_rules_pro_idx on public.availability_rules (pro_id, weekday);

create table public.availability_exceptions (
  id uuid primary key default gen_random_uuid(),
  pro_id uuid not null references public.pros on delete cascade,
  period tstzrange not null check (not isempty(period)),
  kind text not null check (kind in ('off', 'extra')),
  reason text not null default '',
  created_at timestamptz not null default now()
);
create index availability_exceptions_pro_idx on public.availability_exceptions using gist (pro_id, period);

-- Nommé pour s'exécuter après bookings_price (ordre alphabétique), qui
-- calcule le créneau.
create function private.check_availability() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_local timestamp := lower(new.slot) at time zone 'Africa/Abidjan';
  v_local_end timestamp := upper(new.slot) at time zone 'Africa/Abidjan';
begin
  if exists (select 1 from public.availability_exceptions
             where pro_id = new.pro_id and kind = 'off' and period && new.slot) then
    raise exception 'Ce soignant n''est pas disponible à cette date.';
  end if;
  if not exists (select 1 from public.availability_rules where pro_id = new.pro_id) then
    return new;
  end if;
  if exists (select 1 from public.availability_exceptions
             where pro_id = new.pro_id and kind = 'extra' and period @> new.slot) then
    return new;
  end if;
  if not exists (
    select 1 from public.availability_rules r
    where r.pro_id = new.pro_id
      and r.weekday = extract(isodow from v_local)
      and v_local::date = v_local_end::date
      and v_local::time >= r.start_time and v_local_end::time <= r.end_time
  ) then
    raise exception 'Ce créneau est en dehors des disponibilités du soignant.';
  end if;
  return new;
end;
$$;
create trigger bookings_price_zz_availability before insert on public.bookings
  for each row execute function private.check_availability();

-- =========================================================== suivis réguliers
alter table public.contracts
  add column patient_id uuid references public.patients on delete cascade,
  add column pro_id uuid references public.pros,
  add column service_id text references public.services,
  add column status text not null default 'active' check (status in ('active', 'completed', 'cancelled')),
  add column sessions_planned int check (sessions_planned between 2 and 30);

update public.contracts c set patient_id = b.patient_id, pro_id = b.pro_id, service_id = b.service_id,
       sessions_planned = (select count(*) from public.bookings x where x.contract_id = c.id)
  from public.bookings b
  where b.contract_id = c.id and b.session_index = (select min(session_index) from public.bookings y where y.contract_id = c.id)
    and c.patient_id is null;

create index contracts_booked_by_idx on public.contracts (booked_by);
create index contracts_patient_idx on public.contracts (patient_id);
create index contracts_pro_idx on public.contracts (pro_id, status);

create function private.contract_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.contract_id is not null then
    update public.contracts
      set patient_id = coalesce(patient_id, new.patient_id),
          pro_id = coalesce(pro_id, new.pro_id),
          service_id = coalesce(service_id, new.service_id),
          sessions_planned = (select count(*) from public.bookings where contract_id = new.contract_id)
      where id = new.contract_id;
  end if;
  return null;
end;
$$;
create trigger bookings_contract_fill after insert on public.bookings
  for each row execute function private.contract_fill();

-- ================================================================ paiements
-- Argent réel reçu de l'agrégateur (Mobile Money). Écrit uniquement par le
-- serveur (webhook, clé service). wallet_transactions reste le grand livre
-- interne ; payments garde aussi les paiements en attente ou échoués.
create type public.payment_status as enum ('pending', 'succeeded', 'failed', 'refunded');

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  payer_id uuid not null references public.profiles on delete restrict,
  purpose text not null check (purpose in ('topup', 'booking')),
  booking_id uuid references public.bookings on delete set null,
  amount int not null check (amount > 0),
  currency text not null default 'XOF' check (currency = 'XOF'),
  method text not null check (method in ('orange', 'mtn', 'moov', 'wave', 'card')),
  provider text not null default 'aggregator',
  provider_ref text,
  status public.payment_status not null default 'pending',
  failure_reason text,
  raw_event jsonb,               -- charge utile du webhook, sans secret
  created_at timestamptz not null default now(),
  confirmed_at timestamptz,
  check (purpose <> 'booking' or booking_id is not null),
  unique (provider, provider_ref)
);
create index payments_payer_idx on public.payments (payer_id, created_at desc);
create index payments_booking_idx on public.payments (booking_id);
create index payments_status_idx on public.payments (status, created_at) where status = 'pending';

-- ============================================================== commissions
-- Pas de table en double : la commission est figée sur chaque réservation
-- (bookings.commission, commission_rate). Rapport pour la finance :
create function public.admin_commission_report(p_from date, p_to date)
returns table (day date, bookings_done bigint, gross int, commission int, paid_to_pros int)
language plpgsql stable security definer set search_path = '' as $$
begin
  perform private.require_perm('finance');
  return query
    select (b.scheduled_at at time zone 'Africa/Abidjan')::date,
           count(*), sum(b.price)::int, sum(b.commission)::int, sum(b.price - b.commission)::int
    from public.bookings b
    where b.status = 'done'
      and (b.scheduled_at at time zone 'Africa/Abidjan')::date between p_from and p_to
    group by 1 order by 1;
end;
$$;

-- ================================================================== retraits
alter table public.withdrawals
  add column processed_at timestamptz,
  add column processed_by uuid references public.profiles on delete set null,
  add column failure_reason text;
create index withdrawals_status_idx on public.withdrawals (status, created_at) where status = 'pending';

-- Résultat du virement Mobile Money. En cas d'échec, le montant revient
-- sur le solde du soignant (une seule fois, référence unique).
create function public.admin_settle_withdrawal(p_id uuid, p_sent boolean, p_ref text, p_reason text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  w public.withdrawals;
begin
  perform private.require_perm('finance');
  update public.withdrawals
    set status = case when p_sent then 'sent' else 'failed' end,
        external_ref = p_ref, failure_reason = p_reason,
        processed_at = now(), processed_by = (select auth.uid())
    where id = p_id and status = 'pending'
    returning * into w;
  if w.id is null then
    raise exception 'Retrait introuvable ou déjà traité.';
  end if;
  if not p_sent then
    perform private.wallet_move(w.pro_id, 'withdrawal', w.amount, null, 'reversal-' || w.id::text,
      'Retrait non abouti, montant recrédité');
  end if;
end;
$$;

-- ============================================================== abonnements
-- Historique de Pro Premium. pros.premium_until reste la valeur de référence
-- lue par la recherche ; chaque période est aussi enregistrée ici.
create table public.subscriptions (
  id uuid primary key default gen_random_uuid(),
  pro_id uuid not null references public.pros on delete cascade,
  plan text not null default 'premium' check (plan in ('premium')),
  source text not null check (source in ('paid', 'referral', 'admin', 'legacy')),
  amount int not null default 0 check (amount >= 0),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  created_at timestamptz not null default now(),
  check (ends_at > starts_at)
);
create index subscriptions_pro_idx on public.subscriptions (pro_id, ends_at desc);

insert into public.subscriptions (pro_id, source, starts_at, ends_at)
select id, 'legacy', least(now(), premium_until - interval '30 days'), premium_until
from public.pros where premium_until > now();

create or replace function public.subscribe_premium() returns timestamptz
language plpgsql security definer set search_path = '' as $$
declare
  v_price int := private.setting_num('premium_price', 5000)::int;
  v_days int := private.setting_num('premium_days', 30)::int;
  v_start timestamptz;
  v_until timestamptz;
begin
  if not exists (select 1 from public.pros where id = (select auth.uid()) and verification_status = 'verified') then
    raise exception 'Réservé aux soignants vérifiés.';
  end if;
  perform private.wallet_move((select auth.uid()), 'subscription', -v_price, null, null,
    'Abonnement Pro Premium (' || v_days || ' jours)');
  select greatest(coalesce(premium_until, now()), now()) into v_start from public.pros where id = (select auth.uid());
  update public.pros set premium_until = v_start + make_interval(days => v_days)
    where id = (select auth.uid())
    returning premium_until into v_until;
  insert into public.subscriptions (pro_id, source, amount, starts_at, ends_at)
    values ((select auth.uid()), 'paid', v_price, v_start, v_until);
  return v_until;
end;
$$;

-- Validation d'un soignant : permission verify_pros ; le mois offert au
-- parrain est enregistré dans subscriptions. Sinon identique à 0004.
create or replace function public.admin_verify_pro(p_pro uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_type public.pro_type;
  v_referrer uuid;
  v_rewarded boolean;
  v_start timestamptz;
  v_until timestamptz;
begin
  perform private.require_perm('verify_pros');
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
    select greatest(coalesce(premium_until, now()), now()) into v_start from public.pros where id = v_referrer;
    update public.pros set premium_until = v_start + interval '30 days'
      where id = v_referrer returning premium_until into v_until;
    insert into public.subscriptions (pro_id, source, starts_at, ends_at)
      values (v_referrer, 'referral', v_start, v_until);
  end if;
end;
$$;

-- ======================================================= avis : modération
alter table public.reviews
  add column hidden_at timestamptz,
  add column hidden_by uuid references public.profiles on delete set null,
  add column hidden_reason text;

drop policy reviews_select on public.reviews;
create policy reviews_select on public.reviews for select to authenticated
  using (hidden_at is null or pro_id = (select auth.uid()) or (select private.has_perm('moderate')));

create function public.admin_hide_review(p_booking uuid, p_hide boolean, p_reason text default null)
returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_pro uuid;
begin
  perform private.require_perm('moderate');
  if p_hide and coalesce(trim(p_reason), '') = '' then
    raise exception 'Indiquez un motif.';
  end if;
  update public.reviews
    set hidden_at = case when p_hide then now() end,
        hidden_by = case when p_hide then (select auth.uid()) end,
        hidden_reason = case when p_hide then p_reason end
    where booking_id = p_booking
    returning pro_id into v_pro;
  if v_pro is null then
    raise exception 'Avis introuvable.';
  end if;
  -- La note moyenne ne compte que les avis visibles.
  update public.pros p set
    rating_count = s.n, rating_avg = coalesce(s.avg, 0)
    from (select count(*)::int n, round(avg(rating)::numeric, 2) avg
          from public.reviews where pro_id = v_pro and hidden_at is null) s
    where p.id = v_pro;
end;
$$;

-- ================================================================ pharmacies
create table public.pharmacies (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 1),
  commune text not null,
  address text not null default '',
  phone text check (phone ~ '^\+?[0-9 ]{8,16}$'),
  location_lat double precision check (location_lat between -90 and 90),
  location_lng double precision check (location_lng between -180 and 180),
  opening_hours jsonb not null default '{}',
  on_duty_from timestamptz,        -- pharmacie de garde
  on_duty_until timestamptz,
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (on_duty_until is null or on_duty_until > on_duty_from)
);
create index pharmacies_commune_idx on public.pharmacies (commune) where active;
create index pharmacies_on_duty_idx on public.pharmacies (on_duty_until) where active and on_duty_until is not null;

-- ============================================================== réclamations
create type public.complaint_status as enum ('open', 'in_review', 'resolved', 'rejected');
create type public.complaint_category as enum
  ('delay', 'no_show', 'quality', 'behavior', 'billing', 'safety', 'other');

create table public.complaints (
  id uuid primary key default gen_random_uuid(),
  opened_by uuid not null references public.profiles on delete cascade,
  booking_id uuid references public.bookings on delete set null,
  pro_id uuid references public.pros on delete set null,
  category public.complaint_category not null,
  description text not null check (length(trim(description)) between 10 and 4000),
  status public.complaint_status not null default 'open',
  priority smallint not null default 2 check (priority between 1 and 3),   -- 1 = urgent
  assigned_to uuid references public.profiles on delete set null,
  resolution text,
  refund_amount int not null default 0 check (refund_amount >= 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  resolved_at timestamptz
);
create index complaints_opened_by_idx on public.complaints (opened_by, created_at desc);
create index complaints_queue_idx on public.complaints (status, priority, created_at) where status in ('open', 'in_review');
create index complaints_booking_idx on public.complaints (booking_id);
create index complaints_pro_idx on public.complaints (pro_id);
create index complaints_assigned_idx on public.complaints (assigned_to);

create function public.open_complaint(p_booking uuid, p_category public.complaint_category, p_description text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_pro uuid;
  v_id uuid;
begin
  if p_booking is not null then
    select pro_id into v_pro from public.bookings
      where id = p_booking and (booked_by = (select auth.uid()) or pro_id = (select auth.uid()));
    if not found then
      raise exception 'Rendez-vous introuvable.';
    end if;
  end if;
  insert into public.complaints (opened_by, booking_id, pro_id, category, description, priority)
    values ((select auth.uid()), p_booking, v_pro, p_category, p_description,
            case when p_category = 'safety' then 1 else 2 end)
    returning id into v_id;
  perform private.notify_admins('Nouvelle réclamation',
    case when p_category = 'safety' then 'Urgent : signalement de sécurité.' else 'Une réclamation est à traiter.' end);
  return v_id;
end;
$$;

-- Traitement par le support ; un geste commercial (remboursement sur le
-- solde) exige en plus la permission finance.
create function public.admin_update_complaint(
  p_id uuid, p_status public.complaint_status, p_resolution text default null,
  p_refund int default 0, p_assign_to uuid default null
) returns void
language plpgsql security definer set search_path = '' as $$
declare
  c public.complaints;
begin
  perform private.require_perm('support');
  if coalesce(p_refund, 0) > 0 then
    perform private.require_perm('finance');
  end if;
  if p_status in ('resolved', 'rejected') and coalesce(trim(p_resolution), '') = '' then
    raise exception 'Indiquez la réponse apportée.';
  end if;
  update public.complaints
    set status = p_status, resolution = coalesce(p_resolution, resolution),
        assigned_to = coalesce(p_assign_to, assigned_to, (select auth.uid())),
        refund_amount = refund_amount + coalesce(p_refund, 0),
        updated_at = now(),
        resolved_at = case when p_status in ('resolved', 'rejected') then now() end
    where id = p_id and status not in ('resolved', 'rejected')
    returning * into c;
  if c.id is null then
    raise exception 'Réclamation introuvable ou déjà close.';
  end if;
  if coalesce(p_refund, 0) > 0 then
    perform private.wallet_move(c.opened_by, 'refund', p_refund, null,
      'complaint-' || c.id::text || '-' || extract(epoch from now())::bigint, 'Geste commercial MyNurse');
  end if;
  if p_status in ('resolved', 'rejected') then
    perform private.notify(c.opened_by, 'Réclamation traitée', coalesce(p_resolution, ''), c.booking_id);
  end if;
end;
$$;


-- Textes de notification : retrait non abouti (montant recrédité) et geste
-- commercial après réclamation. Sinon identique à 0007.
create or replace function private.on_wallet_tx_notify() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.kind = 'topup' then
    perform private.notify(new.owner_id, 'Recharge confirmée',
      private.fcfa(new.amount) || ' ajoutés à votre solde.');
  elsif new.kind = 'withdrawal' and new.amount < 0 then
    perform private.notify(new.owner_id, 'Retrait demandé',
      private.fcfa(-new.amount) || ' vers votre compte Mobile Money.');
  elsif new.kind = 'withdrawal' then
    perform private.notify(new.owner_id, 'Retrait non abouti',
      private.fcfa(new.amount) || ' recrédités sur votre solde.');
  elsif new.kind = 'subscription' then
    perform private.notify(new.owner_id, 'Pro Premium activé',
      'Vous êtes mis en avant pendant 30 jours.');
  elsif new.kind = 'refund' and new.external_ref like 'complaint-%' then
    perform private.notify(new.owner_id, 'Geste commercial',
      private.fcfa(new.amount) || ' crédités sur votre solde suite à votre réclamation.');
  elsif new.kind = 'refund' and new.booking_id is null then
    perform private.notify(new.owner_id, 'Paiement crédité sur votre solde',
      private.fcfa(new.amount) || ' reçus après l’expiration du rendez-vous.');
  end if;
  return null;
end;
$$;

-- ============================================================= notifications
alter table public.notifications
  add column kind text not null default 'info'
  check (kind in ('info', 'booking', 'payment', 'verification', 'security', 'complaint'));
create index notifications_unread_idx on public.notifications (user_id) where read_at is null;

-- ======================================================== index manquants
-- Clés étrangères sans index et requêtes fréquentes (expiration chaque minute).
create index if not exists bookings_service_idx on public.bookings (service_id);
create index if not exists bookings_open_idx on public.bookings (status, scheduled_at)
  where status in ('pending', 'accepted');
create index if not exists pro_cancellations_booking_idx on public.pro_cancellations (booking_id);
create index if not exists wallet_transactions_booking_fk_idx on public.wallet_transactions (booking_id);
create index if not exists pros_referred_by_idx on public.pros (referred_by);
create index if not exists care_logs_booking_pro_idx on public.care_logs (pro_id, created_at desc);

-- ================================================ règles d'accès (RLS)
alter table public.platform_settings enable row level security;
alter table public.availability_rules enable row level security;
alter table public.availability_exceptions enable row level security;
alter table public.payments enable row level security;
alter table public.subscriptions enable row level security;
alter table public.pharmacies enable row level security;
alter table public.complaints enable row level security;

revoke all on public.platform_settings, public.availability_rules, public.availability_exceptions,
  public.payments, public.subscriptions, public.pharmacies, public.complaints from anon, authenticated;

grant select on public.platform_settings to authenticated;
create policy platform_settings_select on public.platform_settings for select to authenticated using (true);

grant select on public.availability_rules, public.availability_exceptions to authenticated;
grant insert (pro_id, weekday, start_time, end_time), delete on public.availability_rules to authenticated;
grant insert (pro_id, period, kind, reason), delete on public.availability_exceptions to authenticated;
create policy availability_rules_select on public.availability_rules for select to authenticated using (true);
create policy availability_rules_insert on public.availability_rules for insert to authenticated
  with check (pro_id = (select auth.uid()));
create policy availability_rules_delete on public.availability_rules for delete to authenticated
  using (pro_id = (select auth.uid()));
-- Les congés ne sont visibles que par le soignant (vie privée) ; la
-- réservation les vérifie côté serveur.
create policy availability_exceptions_select on public.availability_exceptions for select to authenticated
  using (pro_id = (select auth.uid()) or (select private.has_perm('manage_bookings')));
create policy availability_exceptions_insert on public.availability_exceptions for insert to authenticated
  with check (pro_id = (select auth.uid()));
create policy availability_exceptions_delete on public.availability_exceptions for delete to authenticated
  using (pro_id = (select auth.uid()));

grant select on public.payments to authenticated;
create policy payments_select on public.payments for select to authenticated
  using (payer_id = (select auth.uid()) or (select private.has_perm('finance')));

grant select on public.subscriptions to authenticated;
create policy subscriptions_select on public.subscriptions for select to authenticated
  using (pro_id = (select auth.uid()) or (select private.has_perm('finance')));

grant select on public.pharmacies to anon, authenticated;
grant insert, update on public.pharmacies to authenticated;
create policy pharmacies_select on public.pharmacies for select to anon, authenticated
  using (active or (select private.has_perm('manage_settings')));
create policy pharmacies_insert on public.pharmacies for insert to authenticated
  with check ((select private.has_perm('manage_settings')));
create policy pharmacies_update on public.pharmacies for update to authenticated
  using ((select private.has_perm('manage_settings'))) with check ((select private.has_perm('manage_settings')));

grant select on public.complaints to authenticated;
create policy complaints_select on public.complaints for select to authenticated
  using (opened_by = (select auth.uid()) or (select private.has_perm('support')));

-- ============================================================ audit : tables
create trigger platform_settings_audit after insert or update or delete on public.platform_settings
  for each row execute function audit.log_change('full', '', 'key');
create trigger payments_audit after insert or update on public.payments
  for each row execute function audit.log_change('full');
create trigger subscriptions_audit after insert on public.subscriptions
  for each row execute function audit.log_change('full');
create trigger complaints_audit after insert or update on public.complaints
  for each row execute function audit.log_change('full');
create trigger reviews_moderation_audit after update of hidden_at on public.reviews
  for each row execute function audit.log_change('full', '', 'booking_id');
create trigger pro_services_audit after insert or update or delete on public.pro_services
  for each row execute function audit.log_change('full', '', 'pro_id');

-- ========================================================= droits d'exécution
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function
  private.is_admin(), private.require_admin(), private.required_docs(public.pro_type),
  private.owns_patient(uuid), private.treats_patient(uuid),
  private.has_perm(public.staff_permission), private.has_any_perm(public.staff_permission[]),
  private.member_has(uuid, public.member_permission), private.is_member(uuid),
  private.can_act_for(uuid, public.member_permission),
  private.has_record_access(uuid, public.record_scope), private.try_uuid(text)
to authenticated;

revoke execute on function
  public.admin_update_setting(text, jsonb),
  public.admin_commission_report(date, date),
  public.admin_settle_withdrawal(uuid, boolean, text, text),
  public.admin_hide_review(uuid, boolean, text),
  public.open_complaint(uuid, public.complaint_category, text),
  public.admin_update_complaint(uuid, public.complaint_status, text, int, uuid)
from public, anon;
grant execute on function
  public.admin_update_setting(text, jsonb),
  public.admin_commission_report(date, date),
  public.admin_settle_withdrawal(uuid, boolean, text, text),
  public.admin_hide_review(uuid, boolean, text),
  public.open_complaint(uuid, public.complaint_category, text),
  public.admin_update_complaint(uuid, public.complaint_status, text, int, uuid)
to authenticated;
