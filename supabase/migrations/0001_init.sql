-- MyNurse V1 : schéma initial.
-- Principe : le client ne modifie jamais directement un statut, un prix ou une
-- vérification. Ces changements passent par des fonctions contrôlées.

create schema if not exists private;

create type public.user_role as enum ('patient', 'pro', 'admin');
create type public.pro_type as enum ('infirmier', 'aide_soignant', 'medecin', 'kine', 'sage_femme');
create type public.verification_status as enum ('pending', 'verified', 'rejected', 'suspended');
create type public.booking_status as enum ('pending', 'accepted', 'refused', 'cancelled', 'done');

-- ---------------------------------------------------------------- comptes
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  role public.user_role not null default 'patient',
  full_name text not null default '',
  phone text,
  commune text,
  created_at timestamptz not null default now()
);

-- Personnes soignées : un compte peut gérer plusieurs proches.
create table public.patients (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles on delete cascade,
  full_name text not null,
  birth_date date,
  relation text not null default 'moi',
  allergies text not null default '',
  medical_notes text not null default '',
  created_at timestamptz not null default now()
);
create index patients_owner_idx on public.patients (owner_id);

create table public.pros (
  id uuid primary key references public.profiles on delete cascade,
  display_name text not null,
  pro_type public.pro_type not null,
  bio text not null default '',
  years_experience int not null default 0 check (years_experience between 0 and 60),
  communes text[] not null default '{}',
  night_available boolean not null default false,
  order_number text,
  verification_status public.verification_status not null default 'pending',
  rating_avg numeric(3, 2) not null default 0,
  rating_count int not null default 0,
  care_count int not null default 0,
  created_at timestamptz not null default now()
);
create index pros_search_idx on public.pros using gin (communes) where verification_status = 'verified';

-- Pièces justificatives (diplôme, Ordre, CNI) : fichiers dans un bucket privé.
create table public.pro_documents (
  id uuid primary key default gen_random_uuid(),
  pro_id uuid not null references public.pros on delete cascade,
  doc_type text not null check (doc_type in ('diplome', 'autorisation', 'ordre', 'cni', 'rc_pro')),
  storage_path text not null,
  created_at timestamptz not null default now()
);
create index pro_documents_pro_idx on public.pro_documents (pro_id);

-- --------------------------------------------------------------- catalogue
create table public.services (
  id text primary key,
  name text not null,
  pro_type public.pro_type not null,
  min_price int not null check (min_price > 0),
  max_price int not null,
  needs_prescription boolean not null default false,
  active boolean not null default true,
  check (max_price >= min_price)
);

create table public.pro_services (
  pro_id uuid not null references public.pros on delete cascade,
  service_id text not null references public.services,
  price int not null check (price > 0),
  primary key (pro_id, service_id)
);
create index pro_services_service_idx on public.pro_services (service_id);

-- ------------------------------------------------------------ réservations
create table public.bookings (
  id uuid primary key default gen_random_uuid(),
  booked_by uuid not null references public.profiles,
  patient_id uuid not null references public.patients,
  pro_id uuid not null references public.pros,
  service_id text not null references public.services,
  commune text not null,
  address text not null check (length(address) >= 8),
  scheduled_at timestamptz not null,
  has_prescription boolean not null default false,
  note text not null default '',
  -- Calculés par le serveur à la création (voir private.price_booking).
  base_price int not null default 0,
  night boolean not null default false,
  price int not null default 0,
  commission int not null default 0,
  status public.booking_status not null default 'pending',
  created_at timestamptz not null default now()
);
create index bookings_booked_by_idx on public.bookings (booked_by, scheduled_at desc);
create index bookings_pro_idx on public.bookings (pro_id, status, scheduled_at);
create index bookings_patient_idx on public.bookings (patient_id);

create table public.care_logs (
  booking_id uuid primary key references public.bookings on delete cascade,
  pro_id uuid not null references public.pros,
  arrived_at timestamptz not null,
  left_at timestamptz not null,
  blood_pressure text not null default '',
  temperature text not null default '',
  pulse text not null default '',
  glycemia text not null default '',
  acts text not null check (length(trim(acts)) > 0),
  observations text not null default '',
  created_at timestamptz not null default now(),
  check (left_at > arrived_at)
);
create index care_logs_pro_idx on public.care_logs (pro_id);

create table public.reviews (
  booking_id uuid primary key references public.bookings on delete cascade,
  pro_id uuid not null references public.pros,
  rating int not null check (rating between 1 and 5),
  comment text not null default '',
  created_at timestamptz not null default now()
);
create index reviews_pro_idx on public.reviews (pro_id);

-- ------------------------------------------------------- fonctions internes
create function private.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin');
$$;

-- Ces deux contrôles passent par des fonctions pour éviter que les règles
-- d'accès de patients et de bookings se référencent en boucle.
create function private.owns_patient(p_patient uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.patients where id = p_patient and owner_id = (select auth.uid()));
$$;

create function private.treats_patient(p_patient uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.bookings
    where patient_id = p_patient and pro_id = (select auth.uid()) and status in ('accepted', 'done')
  );
$$;

-- Crée le profil à l'inscription. Le rôle admin ne peut pas être demandé.
create function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    case when new.raw_user_meta_data ->> 'role' = 'pro' then 'pro'::public.user_role else 'patient'::public.user_role end,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.phone
  );
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function private.handle_new_user();

-- Fixe le prix côté serveur : tarif du pro, majoration de nuit de 50 %
-- (21 h - 6 h, heure d'Abidjan), commission de 15 %.
create function private.price_booking() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_price int;
  v_hour int;
  v_night_ok boolean;
  v_needs_rx boolean;
begin
  select ps.price, p.night_available, s.needs_prescription
    into v_price, v_night_ok, v_needs_rx
  from public.pro_services ps
  join public.pros p on p.id = ps.pro_id
  join public.services s on s.id = ps.service_id
  where ps.pro_id = new.pro_id and ps.service_id = new.service_id
    and p.verification_status = 'verified' and s.active
    and new.commune = any (p.communes);
  if v_price is null then
    raise exception 'Ce soignant ne propose pas ce soin dans cette commune.';
  end if;
  if new.scheduled_at <= now() then
    raise exception 'La date du soin doit être à venir.';
  end if;
  if v_needs_rx and not new.has_prescription then
    raise exception 'Ce soin se fait uniquement sur ordonnance.';
  end if;
  v_hour := extract(hour from new.scheduled_at at time zone 'Africa/Abidjan');
  new.night := v_hour >= 21 or v_hour < 6;
  if new.night and not v_night_ok then
    raise exception 'Ce soignant ne fait pas de soins de nuit.';
  end if;
  new.base_price := v_price;
  new.price := case when new.night then round(v_price * 1.5) else v_price end;
  new.commission := round(new.price * 0.15);
  new.status := 'pending';
  return new;
end;
$$;
create trigger bookings_price before insert on public.bookings
  for each row execute function private.price_booking();

-- Un soignant ne propose que les soins de sa profession.
create function private.check_pro_service() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (
    select 1 from public.pros p join public.services s on s.pro_type = p.pro_type
    where p.id = new.pro_id and s.id = new.service_id
  ) then
    raise exception 'Ce soin ne correspond pas à votre profession.';
  end if;
  return new;
end;
$$;
create trigger pro_services_check before insert or update on public.pro_services
  for each row execute function private.check_pro_service();

-- Le compte rendu clôture le soin.
create function private.on_care_log() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.bookings set status = 'done'
    where id = new.booking_id and pro_id = new.pro_id and status = 'accepted';
  if not found then
    raise exception 'Ce soin n''est pas confirmé ou ne vous est pas attribué.';
  end if;
  update public.pros set care_count = care_count + 1 where id = new.pro_id;
  return new;
end;
$$;
create trigger care_logs_close after insert on public.care_logs
  for each row execute function private.on_care_log();

create function private.on_review() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  update public.pros set
    rating_avg = round((rating_avg * rating_count + new.rating)::numeric / (rating_count + 1), 2),
    rating_count = rating_count + 1
  where id = new.pro_id;
  return new;
end;
$$;
create trigger reviews_rating after insert on public.reviews
  for each row execute function private.on_review();

-- ------------------------------------------------- actions appelées par l'app
create function public.respond_booking(p_booking uuid, p_accept boolean) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.bookings
    set status = case when p_accept then 'accepted' else 'refused' end::public.booking_status
    where id = p_booking and pro_id = (select auth.uid()) and status = 'pending';
  if not found then
    raise exception 'Demande introuvable ou déjà traitée.';
  end if;
end;
$$;

create function public.cancel_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.bookings set status = 'cancelled'
    where id = p_booking and booked_by = (select auth.uid()) and status in ('pending', 'accepted');
  if not found then
    raise exception 'Ce soin ne peut plus être annulé.';
  end if;
end;
$$;

create function public.admin_set_pro_status(p_pro uuid, p_status public.verification_status) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not private.is_admin() then
    raise exception 'Réservé à l''administration.';
  end if;
  update public.pros set verification_status = p_status where id = p_pro;
end;
$$;

revoke execute on function public.respond_booking(uuid, boolean) from public, anon;
revoke execute on function public.cancel_booking(uuid) from public, anon;
revoke execute on function public.admin_set_pro_status(uuid, public.verification_status) from public, anon;
grant execute on function public.respond_booking(uuid, boolean) to authenticated;
grant execute on function public.cancel_booking(uuid) to authenticated;
grant execute on function public.admin_set_pro_status(uuid, public.verification_status) to authenticated;
grant usage on schema private to authenticated;
grant execute on function private.is_admin() to authenticated;
grant execute on function private.owns_patient(uuid) to authenticated;
grant execute on function private.treats_patient(uuid) to authenticated;

-- ------------------------------------------------------------ droits d'accès
alter table public.profiles enable row level security;
alter table public.patients enable row level security;
alter table public.pros enable row level security;
alter table public.pro_documents enable row level security;
alter table public.services enable row level security;
alter table public.pro_services enable row level security;
alter table public.bookings enable row level security;
alter table public.care_logs enable row level security;
alter table public.reviews enable row level security;

-- Colonnes modifiables par le client : jamais le rôle, le statut de
-- vérification, les notes, les prix calculés ni le statut d'un soin.
revoke all on all tables in schema public from anon, authenticated;
grant select on public.services to anon, authenticated;
grant select on public.profiles, public.pros, public.pro_services, public.reviews,
  public.bookings, public.care_logs, public.pro_documents to authenticated;
grant update (full_name, commune) on public.profiles to authenticated;
grant select, insert, update, delete on public.patients to authenticated;
grant insert (id, display_name, pro_type, bio, years_experience, communes, night_available, order_number)
  on public.pros to authenticated;
grant update (display_name, bio, years_experience, communes, night_available) on public.pros to authenticated;
grant insert, update, delete on public.pro_services to authenticated;
grant insert, delete on public.pro_documents to authenticated;
grant insert (id, booked_by, patient_id, pro_id, service_id, commune, address, scheduled_at, has_prescription, note)
  on public.bookings to authenticated;
grant insert on public.care_logs, public.reviews to authenticated;

create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.is_admin()));
create policy profiles_update on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy patients_owner on public.patients for all to authenticated
  using (owner_id = (select auth.uid())) with check (owner_id = (select auth.uid()));
-- Le soignant voit la fiche des patients dont il a un soin en cours ou terminé.
create policy patients_pro on public.patients for select to authenticated
  using ((select private.treats_patient(id)));

create policy pros_select on public.pros for select to authenticated
  using (verification_status = 'verified' or id = (select auth.uid()) or (select private.is_admin()));
create policy pros_insert on public.pros for insert to authenticated
  with check (
    id = (select auth.uid())
    and exists (select 1 from public.profiles pr where pr.id = (select auth.uid()) and pr.role = 'pro')
  );
create policy pros_update on public.pros for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy pro_documents_select on public.pro_documents for select to authenticated
  using (pro_id = (select auth.uid()) or (select private.is_admin()));
create policy pro_documents_insert on public.pro_documents for insert to authenticated
  with check (pro_id = (select auth.uid()));
create policy pro_documents_delete on public.pro_documents for delete to authenticated
  using (pro_id = (select auth.uid()));

create policy services_select on public.services for select to anon, authenticated using (active);

create policy pro_services_select on public.pro_services for select to authenticated using (true);
create policy pro_services_insert on public.pro_services for insert to authenticated
  with check (pro_id = (select auth.uid()));
create policy pro_services_update on public.pro_services for update to authenticated
  using (pro_id = (select auth.uid())) with check (pro_id = (select auth.uid()));
create policy pro_services_delete on public.pro_services for delete to authenticated
  using (pro_id = (select auth.uid()));

create policy bookings_select on public.bookings for select to authenticated
  using (booked_by = (select auth.uid()) or pro_id = (select auth.uid()) or (select private.is_admin()));
create policy bookings_insert on public.bookings for insert to authenticated
  with check (
    booked_by = (select auth.uid())
    and private.owns_patient(patient_id)
  );

create policy care_logs_select on public.care_logs for select to authenticated
  using (exists (
    select 1 from public.bookings b
    where b.id = booking_id
      and (b.booked_by = (select auth.uid()) or b.pro_id = (select auth.uid()) or (select private.is_admin()))
  ));
create policy care_logs_insert on public.care_logs for insert to authenticated
  with check (pro_id = (select auth.uid()));

create policy reviews_select on public.reviews for select to authenticated using (true);
create policy reviews_insert on public.reviews for insert to authenticated
  with check (exists (
    select 1 from public.bookings b
    where b.id = booking_id and b.booked_by = (select auth.uid())
      and b.pro_id = reviews.pro_id and b.status = 'done'
  ));

-- ----------------------------------------------------------------- catalogue
insert into public.services (id, name, pro_type, min_price, max_price, needs_prescription) values
  ('injection', 'Injection (IM, sous-cutanée, IV)', 'infirmier', 5000, 8000, true),
  ('perfusion', 'Perfusion (pose + surveillance)', 'infirmier', 15000, 25000, true),
  ('pansement', 'Pansement simple ou complexe', 'infirmier', 5000, 15000, false),
  ('sonde', 'Pose ou changement de sonde urinaire', 'infirmier', 10000, 15000, true),
  ('toilette', 'Toilette au lit, aide à la mobilisation', 'aide_soignant', 5000, 12000, false),
  ('consultation', 'Consultation à domicile', 'medecin', 15000, 30000, false),
  ('kine', 'Séance de kinésithérapie à domicile', 'kine', 10000, 15000, true),
  ('suivi_grossesse', 'Suivi de grossesse à domicile', 'sage_femme', 10000, 15000, false);
