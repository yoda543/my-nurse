-- Schéma de référence après 0011 (généré par pg_dump sur la base de test locale).
-- Lecture seule : ne pas exécuter ; la source de vérité reste supabase/migrations/.
--
-- PostgreSQL database dump
--


-- Dumped from database version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.15 (Ubuntu 16.15-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: audit; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA audit;


--
-- Name: private; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA private;


--
-- Name: public; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA public;


--
-- Name: SCHEMA public; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON SCHEMA public IS 'standard public schema';


--
-- Name: booking_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.booking_status AS ENUM (
    'pending',
    'accepted',
    'refused',
    'cancelled',
    'done'
);


--
-- Name: complaint_category; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.complaint_category AS ENUM (
    'delay',
    'no_show',
    'quality',
    'behavior',
    'billing',
    'safety',
    'other'
);


--
-- Name: complaint_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.complaint_status AS ENUM (
    'open',
    'in_review',
    'resolved',
    'rejected'
);


--
-- Name: medical_doc_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.medical_doc_kind AS ENUM (
    'prescription',
    'lab_result',
    'imaging',
    'report',
    'certificate',
    'other'
);


--
-- Name: member_permission; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.member_permission AS ENUM (
    'view_records',
    'manage_records',
    'book_care',
    'view_reports'
);


--
-- Name: member_relation; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.member_relation AS ENUM (
    'family',
    'caregiver',
    'guardian'
);


--
-- Name: payment_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.payment_status AS ENUM (
    'pending',
    'succeeded',
    'failed',
    'refunded'
);


--
-- Name: pro_type; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.pro_type AS ENUM (
    'infirmier',
    'aide_soignant',
    'medecin',
    'kine',
    'sage_femme'
);


--
-- Name: record_scope; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.record_scope AS ENUM (
    'summary',
    'vitals',
    'documents',
    'reports',
    'full'
);


--
-- Name: staff_permission; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.staff_permission AS ENUM (
    'verify_pros',
    'manage_bookings',
    'finance',
    'support',
    'moderate',
    'audit_read',
    'manage_settings',
    'manage_staff',
    'medical_break_glass'
);


--
-- Name: user_role; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.user_role AS ENUM (
    'patient',
    'pro',
    'admin'
);


--
-- Name: verification_status; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.verification_status AS ENUM (
    'pending',
    'verified',
    'rejected',
    'suspended'
);


--
-- Name: vital_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.vital_kind AS ENUM (
    'blood_pressure',
    'heart_rate',
    'temperature',
    'glycemia',
    'spo2',
    'respiratory_rate',
    'weight',
    'pain_score'
);


--
-- Name: wallet_tx_kind; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.wallet_tx_kind AS ENUM (
    'topup',
    'payment',
    'refund',
    'earning',
    'withdrawal',
    'subscription'
);


--
-- Name: current_role(); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit."current_role"() RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce(
    (select role::text from public.profiles where id = (select auth.uid())),
    current_user::text);
$$;


--
-- Name: forbid_change(); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.forbid_change() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
begin
  raise exception 'Le journal d''audit ne se modifie pas.';
end;
$$;


--
-- Name: log(text, text, text, uuid, text, jsonb); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.log(p_action text, p_entity text, p_entity_id text, p_patient uuid DEFAULT NULL::uuid, p_reason text DEFAULT NULL::text, p_data jsonb DEFAULT NULL::jsonb) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into audit.events (actor_id, actor_role, action, entity, entity_id, patient_id, reason, new_data)
  values ((select auth.uid()), audit.current_role(), p_action, p_entity, p_entity_id, p_patient, p_reason, p_data);
$$;


--
-- Name: log_change(); Type: FUNCTION; Schema: audit; Owner: -
--

CREATE FUNCTION audit.log_change() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_old jsonb := case when tg_op in ('UPDATE', 'DELETE') then to_jsonb(old) end;
  v_new jsonb := case when tg_op in ('INSERT', 'UPDATE') then to_jsonb(new) end;
  v_row jsonb := coalesce(v_new, v_old);
  v_phi boolean := tg_argv[0] = 'phi';
  v_patient uuid;
  v_fields text[];
begin
  if tg_nargs > 1 and tg_argv[1] <> '' then
    v_patient := (v_row ->> tg_argv[1])::uuid;
  end if;
  if tg_op = 'UPDATE' then
    select array_agg(k order by k) into v_fields
      from jsonb_object_keys(v_new) k
      where v_new -> k is distinct from v_old -> k;
    if v_fields is null then
      return null;  -- rien n'a changé
    end if;
  else
    select array_agg(k order by k) into v_fields from jsonb_object_keys(v_row) k;
  end if;
  insert into audit.events (actor_id, actor_role, action, entity, entity_id, patient_id,
                            changed_fields, old_data, new_data)
  values ((select auth.uid()), audit.current_role(), lower(tg_op), tg_table_name,
          v_row ->> coalesce(nullif(case when tg_nargs > 2 then tg_argv[2] end, ''), 'id'),
          v_patient, v_fields,
          case when v_phi then null else v_old end,
          case when v_phi then null else v_new end);
  return null;
end;
$$;


--
-- Name: can_act_for(uuid, public.member_permission); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.can_act_for(p_patient uuid, p_perm public.member_permission) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select private.owns_patient(p_patient) or private.member_has(p_patient, p_perm);
$$;


--
-- Name: care_log_fill(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.care_log_fill() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  select patient_id into new.patient_id from public.bookings where id = new.booking_id;
  return new;
end;
$$;


--
-- Name: care_log_vitals(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.care_log_vitals() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_sys numeric;
  v_dia numeric;
  v numeric;
begin
  begin
    if new.blood_pressure ~ '^\s*[0-9]+([.,][0-9]+)?\s*/\s*[0-9]+([.,][0-9]+)?' then
      v_sys := private.num(split_part(new.blood_pressure, '/', 1));
      v_dia := private.num(split_part(new.blood_pressure, '/', 2));
      if v_sys < 30 then v_sys := v_sys * 10; v_dia := v_dia * 10; end if;  -- cmHg → mmHg
      insert into public.vital_signs (patient_id, kind, value, value2, unit, measured_at, booking_id, recorded_by)
        values (new.patient_id, 'blood_pressure', v_sys, v_dia, 'mmHg', new.arrived_at, new.booking_id, new.pro_id);
    end if;
  exception when others then null;
  end;
  begin
    v := private.num(new.temperature);
    if v is not null then
      insert into public.vital_signs (patient_id, kind, value, unit, measured_at, booking_id, recorded_by)
        values (new.patient_id, 'temperature', v, '°C', new.arrived_at, new.booking_id, new.pro_id);
    end if;
  exception when others then null;
  end;
  begin
    v := private.num(new.pulse);
    if v is not null then
      insert into public.vital_signs (patient_id, kind, value, unit, measured_at, booking_id, recorded_by)
        values (new.patient_id, 'heart_rate', v, 'bpm', new.arrived_at, new.booking_id, new.pro_id);
    end if;
  exception when others then null;
  end;
  begin
    v := private.num(new.glycemia);
    if v > 20 then v := v / 100; end if;  -- mg/dL → g/L
    if v is not null then
      insert into public.vital_signs (patient_id, kind, value, unit, measured_at, booking_id, recorded_by)
        values (new.patient_id, 'glycemia', v, 'g/L', new.arrived_at, new.booking_id, new.pro_id);
    end if;
  exception when others then null;
  end;
  return null;
end;
$$;


--
-- Name: check_availability(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.check_availability() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: check_pro_service(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.check_pro_service() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: check_pro_service_price(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.check_pro_service_price() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: check_referral(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.check_referral() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if new.referred_by is not null and (new.referred_by = new.id or not exists (
    select 1 from public.pros where id = new.referred_by and verification_status = 'verified'
  )) then
    raise exception 'Code de parrainage inconnu.';
  end if;
  return new;
end;
$$;


--
-- Name: check_vital_sign(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.check_vital_sign() RETURNS trigger
    LANGUAGE plpgsql
    SET search_path TO ''
    AS $$
declare
  v_min numeric;
  v_max numeric;
begin
  select u, lo, hi into new.unit, v_min, v_max from (values
    ('blood_pressure'::public.vital_kind, 'mmHg', 40, 300),
    ('heart_rate', 'bpm', 20, 250),
    ('temperature', '°C', 30, 45),
    ('glycemia', 'g/L', 0.2, 6),
    ('spo2', '%', 50, 100),
    ('respiratory_rate', '/min', 4, 80),
    ('weight', 'kg', 0.5, 400),
    ('pain_score', '/10', 0, 10)
  ) t(k, u, lo, hi) where k = new.kind;
  if new.value < v_min or new.value > v_max then
    raise exception 'Valeur improbable pour %.', new.kind;
  end if;
  if new.kind = 'blood_pressure' and (new.value2 < 20 or new.value2 >= new.value) then
    raise exception 'Tension diastolique improbable.';
  end if;
  if new.measured_at > now() + interval '5 minutes' then
    raise exception 'La mesure ne peut pas être dans le futur.';
  end if;
  if tg_op = 'UPDATE' and (new.patient_id, new.kind, new.value, new.value2, new.measured_at, new.recorded_by)
       is distinct from (old.patient_id, old.kind, old.value, old.value2, old.measured_at, old.recorded_by) then
    raise exception 'Une mesure ne se modifie pas : marquez-la comme erronée et saisissez-en une nouvelle.';
  end if;
  return new;
end;
$$;


--
-- Name: contract_fill(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.contract_fill() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: fcfa(integer); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.fcfa(p integer) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select replace(to_char(p, 'FM999,999,999'), ',', ' ') || ' FCFA';
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: bookings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.bookings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booked_by uuid NOT NULL,
    patient_id uuid NOT NULL,
    pro_id uuid NOT NULL,
    service_id text NOT NULL,
    commune text NOT NULL,
    address text NOT NULL,
    scheduled_at timestamp with time zone NOT NULL,
    has_prescription boolean DEFAULT false NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    base_price integer DEFAULT 0 NOT NULL,
    night boolean DEFAULT false NOT NULL,
    price integer DEFAULT 0 NOT NULL,
    commission integer DEFAULT 0 NOT NULL,
    status public.booking_status DEFAULT 'pending'::public.booking_status NOT NULL,
    payment_method text,
    payment_ref text,
    paid_at timestamp with time zone,
    refunded boolean DEFAULT false NOT NULL,
    cancel_reason text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    accepted_at timestamp with time zone,
    commission_rate numeric(4,2) DEFAULT 0.10 NOT NULL,
    contract_id uuid,
    session_index integer DEFAULT 0 NOT NULL,
    cancellation_fee integer DEFAULT 0 NOT NULL,
    receipt_number text,
    slot tstzrange,
    location_lat double precision,
    location_lng double precision,
    CONSTRAINT bookings_address_check CHECK ((length(address) >= 8)),
    CONSTRAINT bookings_location_lat_check CHECK (((location_lat >= ('-90'::integer)::double precision) AND (location_lat <= (90)::double precision))),
    CONSTRAINT bookings_location_lng_check CHECK (((location_lng >= ('-180'::integer)::double precision) AND (location_lng <= (180)::double precision))),
    CONSTRAINT bookings_payment_method_check CHECK ((payment_method = ANY (ARRAY['wallet'::text, 'orange'::text, 'mtn'::text, 'moov'::text, 'wave'::text])))
);


--
-- Name: first_of_group(public.bookings, public.booking_status); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.first_of_group(b public.bookings, p_status public.booking_status) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select b.contract_id is null or b.session_index = (
    select min(session_index) from public.bookings
    where contract_id = b.contract_id and status = p_status
      and cancel_reason is not distinct from b.cancel_reason
  );
$$;


--
-- Name: handle_new_user(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.handle_new_user() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    case when new.raw_user_meta_data ->> 'role' = 'pro' then 'pro'::public.user_role else 'patient'::public.user_role end,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.phone
  );
  insert into public.wallets (owner_id) values (new.id);
  return new;
end;
$$;


--
-- Name: has_any_perm(public.staff_permission[]); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.has_any_perm(p_perms public.staff_permission[]) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.staff_permissions sp
    join public.profiles p on p.id = sp.profile_id
    where sp.profile_id = (select auth.uid()) and p.role = 'admin' and sp.permission = any (p_perms)
  );
$$;


--
-- Name: has_perm(public.staff_permission); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.has_perm(p_perm public.staff_permission) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.staff_permissions sp
    join public.profiles p on p.id = sp.profile_id
    where sp.profile_id = (select auth.uid()) and p.role = 'admin' and sp.permission = p_perm
  );
$$;


--
-- Name: has_record_access(uuid, public.record_scope); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.has_record_access(p_patient uuid, p_scope public.record_scope) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select private.owns_patient(p_patient)
    or private.member_has(p_patient, 'view_records')
    or (p_scope = 'reports' and private.member_has(p_patient, 'view_reports'))
    or exists (
      select 1 from public.record_access_grants g
      where g.patient_id = p_patient and g.grantee_id = (select auth.uid())
        and g.revoked_at is null and now() >= g.starts_at and now() < g.expires_at
        and (p_scope = any (g.scopes) or 'full' = any (g.scopes))
    );
$$;


--
-- Name: is_admin(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.is_admin() RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.profiles where id = (select auth.uid()) and role = 'admin');
$$;


--
-- Name: is_member(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.is_member(p_patient uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.patient_members m
    where m.patient_id = p_patient and m.member_id = (select auth.uid())
      and m.revoked_at is null and (m.expires_at is null or m.expires_at > now())
  );
$$;


--
-- Name: late_fee(public.bookings); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.late_fee(b public.bookings) RETURNS integer
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select case
    when b.paid_at is null then 0
    when b.scheduled_at - now() >= interval '2 hours' then 0
    else round(b.price * 0.5)::int end;
$$;


--
-- Name: member_has(uuid, public.member_permission); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.member_has(p_patient uuid, p_perm public.member_permission) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.patient_members m
    where m.patient_id = p_patient and m.member_id = (select auth.uid())
      and m.revoked_at is null and (m.expires_at is null or m.expires_at > now())
      and p_perm = any (m.permissions)
  );
$$;


--
-- Name: notify(uuid, text, text, uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.notify(p_user uuid, p_title text, p_body text, p_booking uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into public.notifications (user_id, title, body, booking_id)
  select p_user, p_title, p_body, p_booking where p_user is not null;
$$;


--
-- Name: notify_admins(text, text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.notify_admins(p_title text, p_body text) RETURNS void
    LANGUAGE sql SECURITY DEFINER
    SET search_path TO ''
    AS $$
  insert into public.notifications (user_id, title, body)
  select id, p_title, p_body from public.profiles where role = 'admin';
$$;


--
-- Name: num(text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.num(p text) RETURNS numeric
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
begin
  return nullif(replace(substring(p from '[0-9]+(?:[.,][0-9]+)?'), ',', '.'), '')::numeric;
exception when others then
  return null;
end;
$$;


--
-- Name: on_booking_insert_notify(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_booking_insert_notify() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: on_booking_update_notify(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_booking_update_notify() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: on_care_log(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_care_log() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: on_pro_cancellation_notify(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_pro_cancellation_notify() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if (select count(*) from public.pro_cancellations
      where pro_id = new.pro_id and created_at > now() - interval '30 days') = 2 then
    perform private.notify_admins('Alerte fiabilité',
      private.pro_name(new.pro_id) || ' a annulé 2 soins confirmés en 30 jours.');
  end if;
  return null;
end;
$$;


--
-- Name: on_pro_notify(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_pro_notify() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: on_profile_name_notify(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_profile_name_notify() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if old.full_name = '' and new.full_name <> '' and new.role = 'patient' then
    perform private.notify(new.id, 'Bienvenue sur MyNurse',
      'Rechargez votre solde, puis réservez un soignant vérifié près de chez vous.');
  end if;
  return null;
end;
$$;


--
-- Name: on_review(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_review() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.pros set
    rating_avg = round((rating_avg * rating_count + new.rating)::numeric / (rating_count + 1), 2),
    rating_count = rating_count + 1
  where id = new.pro_id;
  return new;
end;
$$;


--
-- Name: on_review_notify(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_review_notify() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform private.notify(new.pro_id, 'Nouvelle note : ' || new.rating || '/5',
    case when new.comment = '' then 'Merci pour votre soin.' else '« ' || new.comment || ' »' end,
    new.booking_id);
  return null;
end;
$$;


--
-- Name: on_wallet_tx_notify(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.on_wallet_tx_notify() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: owns_patient(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.owns_patient(p_patient uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (select 1 from public.patients where id = p_patient and owner_id = (select auth.uid()));
$$;


--
-- Name: patient_name(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.patient_name(p uuid) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select full_name from public.patients where id = p), 'Le patient');
$$;


--
-- Name: payable_group(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.payable_group(p_booking uuid) RETURNS SETOF public.bookings
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select o.* from public.bookings b
  join public.bookings o on o.id = b.id or (b.contract_id is not null and o.contract_id = b.contract_id)
  where b.id = p_booking and o.status = 'accepted' and o.paid_at is null
    and now() < private.payment_deadline(o);
$$;


--
-- Name: payment_deadline(public.bookings); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.payment_deadline(b public.bookings) RETURNS timestamp with time zone
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select least(b.accepted_at + interval '2 hours', b.scheduled_at);
$$;


--
-- Name: price_booking(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.price_booking() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: pro_name(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.pro_name(p uuid) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select display_name from public.pros where id = p), 'Le soignant');
$$;


--
-- Name: refund_booking(uuid, integer); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.refund_booking(p_booking uuid, p_fee integer DEFAULT 0) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: require_admin(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.require_admin() RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not private.is_admin() then
    raise exception 'Réservé à l''administration.';
  end if;
end;
$$;


--
-- Name: require_perm(public.staff_permission); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.require_perm(p_perm public.staff_permission) RETURNS void
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not private.has_perm(p_perm) then
    raise exception 'Action réservée (permission % requise).', p_perm;
  end if;
end;
$$;


--
-- Name: required_docs(public.pro_type); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.required_docs(p_type public.pro_type) RETURNS text[]
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select case when p_type in ('infirmier', 'medecin', 'sage_femme')
    then array['diplome', 'autorisation', 'ordre', 'cni', 'rc_pro']
    else array['diplome', 'autorisation', 'cni', 'rc_pro'] end;
$$;


--
-- Name: response_deadline(public.bookings); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.response_deadline(b public.bookings) RETURNS timestamp with time zone
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select least(b.created_at + interval '2 hours', b.scheduled_at);
$$;


--
-- Name: service_name(text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.service_name(p text) RETURNS text
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select name from public.services where id = p), 'Soin');
$$;


--
-- Name: setting_num(text, numeric); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.setting_num(p_key text, p_default numeric) RETURNS numeric
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select coalesce((select (value #>> '{}')::numeric from public.platform_settings where key = p_key), p_default);
$$;


--
-- Name: sync_booking_grant(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.sync_booking_grant() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_end timestamptz := coalesce(upper(new.slot), new.scheduled_at + interval '2 hours') + interval '24 hours';
begin
  if tg_op = 'INSERT' then
    insert into public.record_access_grants (patient_id, grantee_id, scopes, source, booking_id, reason, expires_at)
    values (new.patient_id, new.pro_id, '{summary}', 'booking', new.id, 'Demande de soin', v_end)
    on conflict (booking_id) where source = 'booking' do nothing;
  elsif new.status is distinct from old.status then
    if new.status = 'accepted' then
      update public.record_access_grants
        set scopes = '{summary,vitals,documents,reports}', expires_at = v_end
        where booking_id = new.id and source = 'booking' and revoked_at is null;
    elsif new.status in ('refused', 'cancelled') then
      update public.record_access_grants
        set revoked_at = now(), revoke_reason = 'Soin ' || new.status::text
        where booking_id = new.id and source = 'booking' and revoked_at is null;
    end if;
  end if;
  return null;
end;
$$;


--
-- Name: sync_medical_record_from_patient(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.sync_medical_record_from_patient() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  insert into public.medical_records (patient_id, allergies, current_treatments, history, updated_by)
    values (new.id, new.allergies, new.treatments, new.history, (select auth.uid()))
  on conflict (patient_id) do update
    set allergies = excluded.allergies, current_treatments = excluded.current_treatments,
        history = excluded.history, updated_at = now(), updated_by = excluded.updated_by
    where (public.medical_records.allergies, public.medical_records.current_treatments, public.medical_records.history)
          is distinct from (excluded.allergies, excluded.current_treatments, excluded.history);
  return null;
end;
$$;


--
-- Name: touch_medical_record(); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.touch_medical_record() RETURNS trigger
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  new.updated_at := now();
  new.updated_by := coalesce((select auth.uid()), new.updated_by);
  return new;
end;
$$;


--
-- Name: treats_patient(uuid); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.treats_patient(p_patient uuid) RETURNS boolean
    LANGUAGE sql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
  select exists (
    select 1 from public.bookings
    where patient_id = p_patient and pro_id = (select auth.uid())
      and status in ('pending', 'accepted', 'done')
  );
$$;


--
-- Name: try_uuid(text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.try_uuid(p text) RETURNS uuid
    LANGUAGE plpgsql IMMUTABLE
    SET search_path TO ''
    AS $$
begin
  return p::uuid;
exception when others then
  return null;
end;
$$;


--
-- Name: wallet_move(uuid, public.wallet_tx_kind, integer, uuid, text, text); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.wallet_move(p_owner uuid, p_kind public.wallet_tx_kind, p_amount integer, p_booking uuid DEFAULT NULL::uuid, p_ref text DEFAULT NULL::text, p_label text DEFAULT ''::text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_balance int;
begin
  insert into public.wallets (owner_id) values (p_owner) on conflict do nothing;
  update public.wallets set balance = balance + p_amount, updated_at = now()
    where owner_id = p_owner and balance + p_amount >= 0
    returning balance into v_balance;
  if v_balance is null then
    raise exception 'Solde insuffisant.';
  end if;
  insert into public.wallet_transactions (owner_id, kind, amount, booking_id, external_ref, label)
    values (p_owner, p_kind, p_amount, p_booking, p_ref, p_label);
  return v_balance;
end;
$$;


--
-- Name: when_label(timestamp with time zone); Type: FUNCTION; Schema: private; Owner: -
--

CREATE FUNCTION private.when_label(p timestamp with time zone) RETURNS text
    LANGUAGE sql IMMUTABLE
    SET search_path TO ''
    AS $$
  select to_char(p at time zone 'Africa/Abidjan', 'DD/MM à HH24"h"MI');
$$;


--
-- Name: add_patient_member(uuid, text, public.member_relation, public.member_permission[], timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.add_patient_member(p_patient uuid, p_contact text, p_relation public.member_relation, p_permissions public.member_permission[], p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_member uuid;
  v_id uuid;
begin
  if not private.owns_patient(p_patient) then
    raise exception 'Seul le titulaire peut ajouter un proche.';
  end if;
  -- Recherche par e-mail ou téléphone. Message neutre : on ne révèle pas
  -- si un compte existe.
  select u.id into v_member from auth.users u
    left join public.profiles p on p.id = u.id
    where lower(u.email) = lower(trim(p_contact)) or p.phone = trim(p_contact) or u.phone = trim(p_contact)
    limit 1;
  if v_member is null or v_member = (select auth.uid()) then
    raise exception 'Invitation impossible. Vérifiez que cette personne a un compte MyNurse.';
  end if;
  insert into public.patient_members (patient_id, member_id, relation, permissions, invited_by, expires_at)
    values (p_patient, v_member, p_relation, p_permissions, (select auth.uid()), p_expires_at)
    returning id into v_id;
  perform private.notify(v_member, 'Accès à un proche', 'Vous avez été ajouté comme proche ou aidant sur MyNurse.');
  return v_id;
end;
$$;


--
-- Name: events; Type: TABLE; Schema: audit; Owner: -
--

CREATE TABLE audit.events (
    id bigint NOT NULL,
    occurred_at timestamp with time zone DEFAULT now() NOT NULL,
    actor_id uuid,
    actor_role text,
    action text NOT NULL,
    entity text NOT NULL,
    entity_id text,
    patient_id uuid,
    changed_fields text[],
    old_data jsonb,
    new_data jsonb,
    reason text
);


--
-- Name: admin_audit_events(uuid, uuid, text, timestamp with time zone, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_audit_events(p_patient uuid DEFAULT NULL::uuid, p_actor uuid DEFAULT NULL::uuid, p_entity text DEFAULT NULL::text, p_since timestamp with time zone DEFAULT (now() - '30 days'::interval), p_limit integer DEFAULT 200) RETURNS SETOF audit.events
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform private.require_perm('audit_read');
  -- Consulter le journal est lui-même tracé.
  perform audit.log('read', 'audit.events', null, p_patient, 'Consultation du journal');
  return query
    select * from audit.events e
    where (p_patient is null or e.patient_id = p_patient)
      and (p_actor is null or e.actor_id = p_actor)
      and (p_entity is null or e.entity = p_entity)
      and e.occurred_at >= p_since
    order by e.occurred_at desc
    limit least(greatest(p_limit, 1), 1000);
end;
$$;


--
-- Name: admin_break_glass(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_break_glass(p_patient uuid, p_reason text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_id uuid;
  v_owner uuid;
begin
  perform private.require_perm('medical_break_glass');
  if length(trim(coalesce(p_reason, ''))) < 10 then
    raise exception 'Motif détaillé obligatoire (10 caractères minimum).';
  end if;
  select owner_id into v_owner from public.patients where id = p_patient;
  if v_owner is null then
    raise exception 'Patient introuvable.';
  end if;
  insert into public.record_access_grants (patient_id, grantee_id, scopes, source, reason, granted_by, expires_at)
    values (p_patient, (select auth.uid()), '{full}', 'break_glass', p_reason, (select auth.uid()),
            now() + interval '4 hours')
    returning id into v_id;
  perform audit.log('break_glass', 'patients', p_patient::text, p_patient, p_reason);
  perform private.notify(v_owner, 'Accès d''urgence à un dossier',
    'L''équipe MyNurse a consulté un dossier de votre compte. Motif : ' || p_reason);
  perform private.notify_admins('Accès d''urgence', 'Un dossier médical a été ouvert en urgence.');
  return v_id;
end;
$$;


--
-- Name: admin_commission_report(date, date); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_commission_report(p_from date, p_to date) RETURNS TABLE(day date, bookings_done bigint, gross integer, commission integer, paid_to_pros integer)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: admin_hide_review(uuid, boolean, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_hide_review(p_booking uuid, p_hide boolean, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: admin_reject_pro(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_reject_pro(p_pro uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform private.require_perm('verify_pros');
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Indiquez un motif.';
  end if;
  update public.pros set verification_status = 'rejected', rejection_reason = p_reason
    where id = p_pro and verification_status = 'pending';
  if not found then
    raise exception 'Ce dossier n''est pas en attente.';
  end if;
end;
$$;


--
-- Name: admin_reliability_alerts(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_reliability_alerts() RETURNS TABLE(pro_id uuid, display_name text, cancellations bigint)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not private.has_any_perm('{verify_pros,manage_bookings}') then
    raise exception 'Action réservée.';
  end if;
  return query
    select p.id, p.display_name, count(*)
    from public.pro_cancellations c join public.pros p on p.id = c.pro_id
    where c.created_at > now() - interval '30 days'
    group by p.id, p.display_name
    having count(*) >= 2;
end;
$$;


--
-- Name: admin_set_staff_permission(uuid, public.staff_permission, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_set_staff_permission(p_profile uuid, p_perm public.staff_permission, p_grant boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  perform private.require_perm('manage_staff');
  if not exists (select 1 from public.profiles where id = p_profile and role = 'admin') then
    raise exception 'Ce compte n''appartient pas à l''équipe MyNurse.';
  end if;
  if p_grant and p_perm = 'medical_break_glass' and p_profile = (select auth.uid()) then
    raise exception 'Un autre administrateur doit vous attribuer cette permission.';
  end if;
  if p_grant then
    insert into public.staff_permissions (profile_id, permission, granted_by)
      values (p_profile, p_perm, (select auth.uid())) on conflict do nothing;
  else
    delete from public.staff_permissions where profile_id = p_profile and permission = p_perm;
  end if;
end;
$$;


--
-- Name: admin_settle_withdrawal(uuid, boolean, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_settle_withdrawal(p_id uuid, p_sent boolean, p_ref text, p_reason text DEFAULT NULL::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: admin_suspend_pro(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_suspend_pro(p_pro uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_id uuid;
begin
  perform private.require_perm('verify_pros');
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


--
-- Name: admin_update_complaint(uuid, public.complaint_status, text, integer, uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_update_complaint(p_id uuid, p_status public.complaint_status, p_resolution text DEFAULT NULL::text, p_refund integer DEFAULT 0, p_assign_to uuid DEFAULT NULL::uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: admin_update_setting(text, jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_update_setting(p_key text, p_value jsonb) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: admin_verify_pro(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.admin_verify_pro(p_pro uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: bootstrap_staff(uuid, public.staff_permission[]); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.bootstrap_staff(p_profile uuid, p_perms public.staff_permission[]) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if 'medical_break_glass' = any (p_perms) then
    raise exception 'L''accès d''urgence s''attribue par un autre administrateur.';
  end if;
  update public.profiles set role = 'admin' where id = p_profile;
  if not found then
    raise exception 'Compte introuvable.';
  end if;
  insert into public.staff_permissions (profile_id, permission)
    select p_profile, unnest(p_perms) on conflict do nothing;
end;
$$;


--
-- Name: cancel_booking(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.cancel_booking(p_booking uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: confirm_payment(uuid, text, text, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_payment(p_booking uuid, p_method text, p_ref text, p_amount integer) RETURNS text
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: confirm_topup(uuid, integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.confirm_topup(p_owner uuid, p_amount integer, p_method text, p_ref text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if p_amount < 500 or p_amount > 500000 then
    raise exception 'Montant hors limites.';
  end if;
  if coalesce(p_ref, '') = '' then
    raise exception 'Référence de paiement manquante.';
  end if;
  return private.wallet_move(p_owner, 'topup', p_amount, null, p_ref,
    'Recharge ' || p_method);
end;
$$;


--
-- Name: expire_stale_bookings(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.expire_stale_bookings() RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: get_patient_chart(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.get_patient_chart(p_patient uuid) RETURNS jsonb
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_summary boolean := private.has_record_access(p_patient, 'summary');
  v_vitals boolean := private.has_record_access(p_patient, 'vitals');
  v_docs boolean := private.has_record_access(p_patient, 'documents');
  v_reports boolean := private.has_record_access(p_patient, 'reports');
  v_result jsonb;
begin
  if not (v_summary or v_vitals or v_docs or v_reports) then
    raise exception 'Vous n''avez pas accès à ce dossier.';
  end if;

  select jsonb_build_object(
    'patient', case when v_summary then jsonb_build_object(
        'id', p.id, 'full_name', p.full_name, 'birth_date', p.birth_date) end,
    'record', case when v_summary then to_jsonb(r) - 'updated_by' end,
    'vitals', case when v_vitals then (
        select coalesce(jsonb_agg(to_jsonb(v) - 'recorded_by' order by v.measured_at desc), '[]')
        from (select * from public.vital_signs
              where patient_id = p_patient and not entered_in_error
              order by measured_at desc limit 50) v) end,
    'documents', case when v_docs then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'id', d.id, 'kind', d.kind, 'title', d.title, 'document_date', d.document_date,
          'storage_path', d.storage_path, 'mime_type', d.mime_type, 'created_at', d.created_at)
          order by d.created_at desc), '[]')
        from public.medical_documents d where d.patient_id = p_patient and d.deleted_at is null) end,
    'reports', case when v_reports then (
        select coalesce(jsonb_agg(jsonb_build_object(
          'booking_id', c.booking_id, 'arrived_at', c.arrived_at, 'left_at', c.left_at,
          'acts', c.acts, 'observations', c.observations, 'pro_name', pr.display_name)
          order by c.arrived_at desc), '[]')
        from (select * from public.care_logs where patient_id = p_patient
              order by arrived_at desc limit 20) c
        left join public.pros pr on pr.id = c.pro_id) end
  ) into v_result
  from public.patients p
  left join public.medical_records r on r.patient_id = p.id
  where p.id = p_patient;

  if not private.owns_patient(p_patient) then
    perform audit.log('read', 'patient_chart', p_patient::text, p_patient, null,
      jsonb_build_object('summary', v_summary, 'vitals', v_vitals, 'documents', v_docs, 'reports', v_reports));
  end if;
  return v_result;
end;
$$;


--
-- Name: grant_record_access(uuid, uuid, public.record_scope[], timestamp with time zone, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.grant_record_access(p_patient uuid, p_pro uuid, p_scopes public.record_scope[], p_expires_at timestamp with time zone, p_reason text DEFAULT ''::text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_id uuid;
begin
  if not private.owns_patient(p_patient) then
    raise exception 'Seul le titulaire du dossier peut accorder un accès.';
  end if;
  if not exists (select 1 from public.pros where id = p_pro and verification_status = 'verified') then
    raise exception 'Ce soignant n''est pas vérifié.';
  end if;
  if p_expires_at <= now() or p_expires_at > now() + interval '365 days' then
    raise exception 'Durée d''accès : de quelques minutes à 365 jours.';
  end if;
  insert into public.record_access_grants (patient_id, grantee_id, scopes, source, reason, granted_by, expires_at)
    values (p_patient, p_pro, p_scopes, 'patient', coalesce(p_reason, ''), (select auth.uid()), p_expires_at)
    returning id into v_id;
  perform private.notify(p_pro, 'Accès à un dossier', 'Un patient vous a donné accès à son dossier médical.');
  return v_id;
end;
$$;


--
-- Name: my_record_access_log(uuid, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.my_record_access_log(p_patient uuid, p_limit integer DEFAULT 100) RETURNS TABLE(occurred_at timestamp with time zone, actor_name text, actor_role text, action text, entity text, reason text)
    LANGUAGE plpgsql STABLE SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  if not private.owns_patient(p_patient) then
    raise exception 'Réservé au titulaire du dossier.';
  end if;
  return query
    select e.occurred_at,
           coalesce(nullif(pr.display_name, ''), nullif(p.full_name, ''),
                    case when e.actor_role = 'admin' then 'Équipe MyNurse' else 'Système' end),
           e.actor_role, e.action, e.entity, e.reason
    from audit.events e
    left join public.profiles p on p.id = e.actor_id
    left join public.pros pr on pr.id = e.actor_id
    where e.patient_id = p_patient
      and e.actor_id is distinct from (select auth.uid())
    order by e.occurred_at desc
    limit least(greatest(p_limit, 1), 500);
end;
$$;


--
-- Name: open_complaint(uuid, public.complaint_category, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.open_complaint(p_booking uuid, p_category public.complaint_category, p_description text) RETURNS uuid
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: pay_booking_with_wallet(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pay_booking_with_wallet(p_booking uuid) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: pro_cancel_booking(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.pro_cancel_booking(p_booking uuid, p_reason text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: request_withdrawal(integer, text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.request_withdrawal(p_amount integer, p_method text, p_phone text) RETURNS integer
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
declare
  v_balance int;
begin
  if not exists (select 1 from public.pros where id = (select auth.uid())) then
    raise exception 'Réservé aux soignants.';
  end if;
  if p_amount < 1000 then
    raise exception 'Montant minimum : 1 000 FCFA.';
  end if;
  v_balance := private.wallet_move((select auth.uid()), 'withdrawal', -p_amount, null, null, 'Retrait ' || p_method);
  insert into public.withdrawals (pro_id, amount, method, phone)
    values ((select auth.uid()), p_amount, p_method, p_phone);
  return v_balance;
end;
$$;


--
-- Name: respond_booking(uuid, boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.respond_booking(p_booking uuid, p_accept boolean) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: resubmit_pro(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.resubmit_pro() RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.pros set verification_status = 'pending', rejection_reason = ''
    where id = (select auth.uid()) and verification_status = 'rejected';
  if not found then
    raise exception 'Aucun dossier refusé à renvoyer.';
  end if;
end;
$$;


--
-- Name: revoke_patient_member(uuid); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revoke_patient_member(p_member uuid) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.patient_members m set revoked_at = now(), revoked_by = (select auth.uid())
    where m.id = p_member and m.revoked_at is null
      and (private.owns_patient(m.patient_id) or m.member_id = (select auth.uid()));
  if not found then
    raise exception 'Proche introuvable.';
  end if;
end;
$$;


--
-- Name: revoke_record_access(uuid, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.revoke_record_access(p_grant uuid, p_reason text DEFAULT ''::text) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.record_access_grants g
    set revoked_at = now(), revoked_by = (select auth.uid()), revoke_reason = coalesce(p_reason, '')
    where g.id = p_grant and g.revoked_at is null
      and (private.owns_patient(g.patient_id) or g.grantee_id = (select auth.uid()));
  if not found then
    raise exception 'Accès introuvable ou déjà retiré.';
  end if;
end;
$$;


--
-- Name: search_pros(text, text); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.search_pros(p_service text, p_commune text) RETURNS TABLE(id uuid, display_name text, pro_type public.pro_type, price integer, rating_avg numeric, rating_count integer, care_count integer, featured boolean)
    LANGUAGE sql STABLE
    SET search_path TO ''
    AS $$
  select p.id, p.display_name, p.pro_type, ps.price, p.rating_avg, p.rating_count, p.care_count,
         coalesce(p.premium_until > now(), false) as featured
  from public.pros p
  join public.pro_services ps on ps.pro_id = p.id and ps.service_id = p_service
  where p.verification_status = 'verified' and p_commune = any (p.communes)
  order by featured desc, p.rating_avg desc;
$$;


--
-- Name: subscribe_premium(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.subscribe_premium() RETURNS timestamp with time zone
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
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


--
-- Name: update_patient_member(uuid, public.member_permission[], timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.update_patient_member(p_member uuid, p_permissions public.member_permission[], p_expires_at timestamp with time zone DEFAULT NULL::timestamp with time zone) RETURNS void
    LANGUAGE plpgsql SECURITY DEFINER
    SET search_path TO ''
    AS $$
begin
  update public.patient_members m set permissions = p_permissions, expires_at = p_expires_at
    where m.id = p_member and m.revoked_at is null and private.owns_patient(m.patient_id);
  if not found then
    raise exception 'Proche introuvable.';
  end if;
end;
$$;


--
-- Name: events_id_seq; Type: SEQUENCE; Schema: audit; Owner: -
--

ALTER TABLE audit.events ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME audit.events_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: availability_exceptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.availability_exceptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    period tstzrange NOT NULL,
    kind text NOT NULL,
    reason text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT availability_exceptions_kind_check CHECK ((kind = ANY (ARRAY['off'::text, 'extra'::text]))),
    CONSTRAINT availability_exceptions_period_check CHECK ((NOT isempty(period)))
);


--
-- Name: availability_rules; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.availability_rules (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    weekday smallint NOT NULL,
    start_time time without time zone NOT NULL,
    end_time time without time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT availability_rules_check CHECK ((end_time > start_time)),
    CONSTRAINT availability_rules_weekday_check CHECK (((weekday >= 1) AND (weekday <= 7)))
);


--
-- Name: care_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.care_logs (
    booking_id uuid NOT NULL,
    pro_id uuid NOT NULL,
    arrived_at timestamp with time zone NOT NULL,
    left_at timestamp with time zone NOT NULL,
    blood_pressure text DEFAULT ''::text NOT NULL,
    temperature text DEFAULT ''::text NOT NULL,
    pulse text DEFAULT ''::text NOT NULL,
    glycemia text DEFAULT ''::text NOT NULL,
    acts text NOT NULL,
    observations text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    patient_id uuid,
    CONSTRAINT care_logs_acts_check CHECK ((length(TRIM(BOTH FROM acts)) > 0)),
    CONSTRAINT care_logs_check CHECK ((left_at > arrived_at))
);


--
-- Name: complaints; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.complaints (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    opened_by uuid NOT NULL,
    booking_id uuid,
    pro_id uuid,
    category public.complaint_category NOT NULL,
    description text NOT NULL,
    status public.complaint_status DEFAULT 'open'::public.complaint_status NOT NULL,
    priority smallint DEFAULT 2 NOT NULL,
    assigned_to uuid,
    resolution text,
    refund_amount integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    resolved_at timestamp with time zone,
    CONSTRAINT complaints_description_check CHECK (((length(TRIM(BOTH FROM description)) >= 10) AND (length(TRIM(BOTH FROM description)) <= 4000))),
    CONSTRAINT complaints_priority_check CHECK (((priority >= 1) AND (priority <= 3))),
    CONSTRAINT complaints_refund_amount_check CHECK ((refund_amount >= 0))
);


--
-- Name: contracts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.contracts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    booked_by uuid NOT NULL,
    frequency text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    patient_id uuid,
    pro_id uuid,
    service_id text,
    status text DEFAULT 'active'::text NOT NULL,
    sessions_planned integer,
    CONSTRAINT contracts_frequency_check CHECK ((frequency = ANY (ARRAY['daily'::text, 'every_other_day'::text, 'weekly'::text]))),
    CONSTRAINT contracts_sessions_planned_check CHECK (((sessions_planned >= 2) AND (sessions_planned <= 30))),
    CONSTRAINT contracts_status_check CHECK ((status = ANY (ARRAY['active'::text, 'completed'::text, 'cancelled'::text])))
);


--
-- Name: medical_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medical_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    kind public.medical_doc_kind NOT NULL,
    title text NOT NULL,
    storage_path text NOT NULL,
    mime_type text NOT NULL,
    size_bytes integer NOT NULL,
    document_date date,
    booking_id uuid,
    uploaded_by uuid NOT NULL,
    deleted_at timestamp with time zone,
    deleted_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT medical_documents_check CHECK ((storage_path ~~ ((patient_id)::text || '/%'::text))),
    CONSTRAINT medical_documents_mime_type_check CHECK ((mime_type = ANY (ARRAY['application/pdf'::text, 'image/jpeg'::text, 'image/png'::text]))),
    CONSTRAINT medical_documents_size_bytes_check CHECK (((size_bytes >= 1) AND (size_bytes <= 10485760))),
    CONSTRAINT medical_documents_title_check CHECK (((length(TRIM(BOTH FROM title)) >= 1) AND (length(TRIM(BOTH FROM title)) <= 120)))
);


--
-- Name: medical_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.medical_records (
    patient_id uuid NOT NULL,
    blood_group text,
    allergies text DEFAULT ''::text NOT NULL,
    chronic_conditions text DEFAULT ''::text NOT NULL,
    current_treatments text DEFAULT ''::text NOT NULL,
    history text DEFAULT ''::text NOT NULL,
    emergency_contact_name text,
    emergency_contact_phone text,
    primary_doctor text,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_by uuid,
    CONSTRAINT medical_records_blood_group_check CHECK ((blood_group = ANY (ARRAY['A+'::text, 'A-'::text, 'B+'::text, 'B-'::text, 'AB+'::text, 'AB-'::text, 'O+'::text, 'O-'::text]))),
    CONSTRAINT medical_records_emergency_contact_phone_check CHECK ((emergency_contact_phone ~ '^\+?[0-9 ]{8,16}$'::text))
);


--
-- Name: notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title text NOT NULL,
    body text DEFAULT ''::text NOT NULL,
    booking_id uuid,
    read_at timestamp with time zone,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    kind text DEFAULT 'info'::text NOT NULL,
    CONSTRAINT notifications_kind_check CHECK ((kind = ANY (ARRAY['info'::text, 'booking'::text, 'payment'::text, 'verification'::text, 'security'::text, 'complaint'::text])))
);


--
-- Name: patient_members; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patient_members (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    member_id uuid NOT NULL,
    relation public.member_relation NOT NULL,
    permissions public.member_permission[] DEFAULT '{view_reports}'::public.member_permission[] NOT NULL,
    invited_by uuid NOT NULL,
    expires_at timestamp with time zone,
    revoked_at timestamp with time zone,
    revoked_by uuid,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT patient_members_check CHECK (((expires_at IS NULL) OR (expires_at > created_at))),
    CONSTRAINT patient_members_permissions_check CHECK ((cardinality(permissions) > 0))
);


--
-- Name: patients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.patients (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid NOT NULL,
    full_name text NOT NULL,
    birth_date date,
    relation text DEFAULT 'moi'::text NOT NULL,
    allergies text DEFAULT ''::text NOT NULL,
    history text DEFAULT ''::text NOT NULL,
    treatments text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: payments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.payments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    payer_id uuid NOT NULL,
    purpose text NOT NULL,
    booking_id uuid,
    amount integer NOT NULL,
    currency text DEFAULT 'XOF'::text NOT NULL,
    method text NOT NULL,
    provider text DEFAULT 'aggregator'::text NOT NULL,
    provider_ref text,
    status public.payment_status DEFAULT 'pending'::public.payment_status NOT NULL,
    failure_reason text,
    raw_event jsonb,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    confirmed_at timestamp with time zone,
    CONSTRAINT payments_amount_check CHECK ((amount > 0)),
    CONSTRAINT payments_check CHECK (((purpose <> 'booking'::text) OR (booking_id IS NOT NULL))),
    CONSTRAINT payments_currency_check CHECK ((currency = 'XOF'::text)),
    CONSTRAINT payments_method_check CHECK ((method = ANY (ARRAY['orange'::text, 'mtn'::text, 'moov'::text, 'wave'::text, 'card'::text]))),
    CONSTRAINT payments_purpose_check CHECK ((purpose = ANY (ARRAY['topup'::text, 'booking'::text])))
);


--
-- Name: pharmacies; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pharmacies (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name text NOT NULL,
    commune text NOT NULL,
    address text DEFAULT ''::text NOT NULL,
    phone text,
    location_lat double precision,
    location_lng double precision,
    opening_hours jsonb DEFAULT '{}'::jsonb NOT NULL,
    on_duty_from timestamp with time zone,
    on_duty_until timestamp with time zone,
    active boolean DEFAULT true NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pharmacies_check CHECK (((on_duty_until IS NULL) OR (on_duty_until > on_duty_from))),
    CONSTRAINT pharmacies_location_lat_check CHECK (((location_lat >= ('-90'::integer)::double precision) AND (location_lat <= (90)::double precision))),
    CONSTRAINT pharmacies_location_lng_check CHECK (((location_lng >= ('-180'::integer)::double precision) AND (location_lng <= (180)::double precision))),
    CONSTRAINT pharmacies_name_check CHECK ((length(TRIM(BOTH FROM name)) > 1)),
    CONSTRAINT pharmacies_phone_check CHECK ((phone ~ '^\+?[0-9 ]{8,16}$'::text))
);


--
-- Name: platform_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.platform_settings (
    key text NOT NULL,
    value jsonb NOT NULL,
    description text DEFAULT ''::text NOT NULL,
    updated_by uuid,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT platform_settings_key_check CHECK ((key ~ '^[a-z_]+$'::text))
);


--
-- Name: pro_cancellations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_cancellations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    booking_id uuid NOT NULL,
    reason text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pro_documents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_documents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    doc_type text NOT NULL,
    storage_path text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT pro_documents_doc_type_check CHECK ((doc_type = ANY (ARRAY['diplome'::text, 'autorisation'::text, 'ordre'::text, 'cni'::text, 'rc_pro'::text])))
);


--
-- Name: pro_services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pro_services (
    pro_id uuid NOT NULL,
    service_id text NOT NULL,
    price integer NOT NULL,
    CONSTRAINT pro_services_price_check CHECK ((price > 0))
);


--
-- Name: profiles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.profiles (
    id uuid NOT NULL,
    role public.user_role DEFAULT 'patient'::public.user_role NOT NULL,
    full_name text DEFAULT ''::text NOT NULL,
    phone text,
    commune text,
    created_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: pros; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.pros (
    id uuid NOT NULL,
    display_name text NOT NULL,
    pro_type public.pro_type NOT NULL,
    bio text DEFAULT ''::text NOT NULL,
    years_experience integer DEFAULT 0 NOT NULL,
    communes text[] DEFAULT '{}'::text[] NOT NULL,
    night_available boolean DEFAULT false NOT NULL,
    order_number text,
    verification_status public.verification_status DEFAULT 'pending'::public.verification_status NOT NULL,
    rejection_reason text DEFAULT ''::text NOT NULL,
    rating_avg numeric(3,2) DEFAULT 0 NOT NULL,
    rating_count integer DEFAULT 0 NOT NULL,
    care_count integer DEFAULT 0 NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    premium_until timestamp with time zone,
    referred_by uuid,
    referral_rewarded boolean DEFAULT false NOT NULL,
    CONSTRAINT pros_years_experience_check CHECK (((years_experience >= 0) AND (years_experience <= 60)))
);


--
-- Name: receipt_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.receipt_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: record_access_grants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.record_access_grants (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    grantee_id uuid NOT NULL,
    scopes public.record_scope[] NOT NULL,
    source text NOT NULL,
    booking_id uuid,
    reason text DEFAULT ''::text NOT NULL,
    granted_by uuid,
    starts_at timestamp with time zone DEFAULT now() NOT NULL,
    expires_at timestamp with time zone NOT NULL,
    revoked_at timestamp with time zone,
    revoked_by uuid,
    revoke_reason text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT record_access_grants_check CHECK ((expires_at > starts_at)),
    CONSTRAINT record_access_grants_check1 CHECK (((source <> 'booking'::text) OR (booking_id IS NOT NULL))),
    CONSTRAINT record_access_grants_check2 CHECK (((source <> 'break_glass'::text) OR (length(TRIM(BOTH FROM reason)) >= 10))),
    CONSTRAINT record_access_grants_check3 CHECK (((source <> 'break_glass'::text) OR (expires_at <= (starts_at + '04:00:00'::interval)))),
    CONSTRAINT record_access_grants_check4 CHECK ((expires_at <= (starts_at + '366 days'::interval))),
    CONSTRAINT record_access_grants_scopes_check CHECK ((cardinality(scopes) > 0)),
    CONSTRAINT record_access_grants_source_check CHECK ((source = ANY (ARRAY['booking'::text, 'patient'::text, 'break_glass'::text])))
);


--
-- Name: reviews; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.reviews (
    booking_id uuid NOT NULL,
    pro_id uuid NOT NULL,
    rating integer NOT NULL,
    comment text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    hidden_at timestamp with time zone,
    hidden_by uuid,
    hidden_reason text,
    CONSTRAINT reviews_rating_check CHECK (((rating >= 1) AND (rating <= 5)))
);


--
-- Name: services; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.services (
    id text NOT NULL,
    name text NOT NULL,
    pro_type public.pro_type NOT NULL,
    min_price integer NOT NULL,
    max_price integer NOT NULL,
    needs_prescription boolean DEFAULT false NOT NULL,
    active boolean DEFAULT true NOT NULL,
    duration_minutes integer DEFAULT 60 NOT NULL,
    CONSTRAINT services_check CHECK ((max_price >= min_price)),
    CONSTRAINT services_duration_minutes_check CHECK (((duration_minutes >= 15) AND (duration_minutes <= 720))),
    CONSTRAINT services_min_price_check CHECK ((min_price > 0))
);


--
-- Name: staff_permissions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.staff_permissions (
    profile_id uuid NOT NULL,
    permission public.staff_permission NOT NULL,
    granted_by uuid,
    granted_at timestamp with time zone DEFAULT now() NOT NULL
);


--
-- Name: subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    plan text DEFAULT 'premium'::text NOT NULL,
    source text NOT NULL,
    amount integer DEFAULT 0 NOT NULL,
    starts_at timestamp with time zone NOT NULL,
    ends_at timestamp with time zone NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT subscriptions_amount_check CHECK ((amount >= 0)),
    CONSTRAINT subscriptions_check CHECK ((ends_at > starts_at)),
    CONSTRAINT subscriptions_plan_check CHECK ((plan = 'premium'::text)),
    CONSTRAINT subscriptions_source_check CHECK ((source = ANY (ARRAY['paid'::text, 'referral'::text, 'admin'::text, 'legacy'::text])))
);


--
-- Name: vital_signs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.vital_signs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    patient_id uuid NOT NULL,
    kind public.vital_kind NOT NULL,
    value numeric(6,2) NOT NULL,
    value2 numeric(6,2),
    unit text NOT NULL,
    measured_at timestamp with time zone DEFAULT now() NOT NULL,
    booking_id uuid,
    recorded_by uuid NOT NULL,
    note text DEFAULT ''::text NOT NULL,
    entered_in_error boolean DEFAULT false NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT vital_signs_check CHECK (((kind = 'blood_pressure'::public.vital_kind) = (value2 IS NOT NULL))),
    CONSTRAINT vital_signs_note_check CHECK ((length(note) <= 500))
);


--
-- Name: wallet_transactions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallet_transactions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    owner_id uuid NOT NULL,
    kind public.wallet_tx_kind NOT NULL,
    amount integer NOT NULL,
    booking_id uuid,
    external_ref text,
    label text DEFAULT ''::text NOT NULL,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wallet_transactions_amount_check CHECK ((amount <> 0))
);


--
-- Name: wallets; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.wallets (
    owner_id uuid NOT NULL,
    balance integer DEFAULT 0 NOT NULL,
    updated_at timestamp with time zone DEFAULT now() NOT NULL,
    CONSTRAINT wallets_balance_check CHECK ((balance >= 0))
);


--
-- Name: withdrawals; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.withdrawals (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    pro_id uuid NOT NULL,
    amount integer NOT NULL,
    method text NOT NULL,
    phone text NOT NULL,
    status text DEFAULT 'pending'::text NOT NULL,
    external_ref text,
    created_at timestamp with time zone DEFAULT now() NOT NULL,
    processed_at timestamp with time zone,
    processed_by uuid,
    failure_reason text,
    CONSTRAINT withdrawals_amount_check CHECK ((amount >= 1000)),
    CONSTRAINT withdrawals_method_check CHECK ((method = ANY (ARRAY['orange'::text, 'mtn'::text, 'moov'::text, 'wave'::text]))),
    CONSTRAINT withdrawals_phone_check CHECK ((phone ~ '^[0-9]{10}$'::text)),
    CONSTRAINT withdrawals_status_check CHECK ((status = ANY (ARRAY['pending'::text, 'sent'::text, 'failed'::text])))
);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: audit; Owner: -
--

ALTER TABLE ONLY audit.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


--
-- Name: availability_exceptions availability_exceptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_exceptions
    ADD CONSTRAINT availability_exceptions_pkey PRIMARY KEY (id);


--
-- Name: availability_rules availability_rules_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_rules
    ADD CONSTRAINT availability_rules_pkey PRIMARY KEY (id);


--
-- Name: bookings bookings_no_overlap; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_no_overlap EXCLUDE USING gist (pro_id WITH =, slot WITH &&) WHERE ((status = 'accepted'::public.booking_status));


--
-- Name: bookings bookings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (id);


--
-- Name: bookings bookings_receipt_number_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_receipt_number_key UNIQUE (receipt_number);


--
-- Name: care_logs care_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.care_logs
    ADD CONSTRAINT care_logs_pkey PRIMARY KEY (booking_id);


--
-- Name: complaints complaints_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_pkey PRIMARY KEY (id);


--
-- Name: contracts contracts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pkey PRIMARY KEY (id);


--
-- Name: medical_documents medical_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_pkey PRIMARY KEY (id);


--
-- Name: medical_documents medical_documents_storage_path_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_storage_path_key UNIQUE (storage_path);


--
-- Name: medical_records medical_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_records
    ADD CONSTRAINT medical_records_pkey PRIMARY KEY (patient_id);


--
-- Name: notifications notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_pkey PRIMARY KEY (id);


--
-- Name: patient_members patient_members_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_members
    ADD CONSTRAINT patient_members_pkey PRIMARY KEY (id);


--
-- Name: patients patients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_pkey PRIMARY KEY (id);


--
-- Name: payments payments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_pkey PRIMARY KEY (id);


--
-- Name: payments payments_provider_provider_ref_key; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_provider_provider_ref_key UNIQUE (provider, provider_ref);


--
-- Name: pharmacies pharmacies_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pharmacies
    ADD CONSTRAINT pharmacies_pkey PRIMARY KEY (id);


--
-- Name: platform_settings platform_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_settings
    ADD CONSTRAINT platform_settings_pkey PRIMARY KEY (key);


--
-- Name: pro_cancellations pro_cancellations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_cancellations
    ADD CONSTRAINT pro_cancellations_pkey PRIMARY KEY (id);


--
-- Name: pro_documents pro_documents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_documents
    ADD CONSTRAINT pro_documents_pkey PRIMARY KEY (id);


--
-- Name: pro_services pro_services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_services
    ADD CONSTRAINT pro_services_pkey PRIMARY KEY (pro_id, service_id);


--
-- Name: profiles profiles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_pkey PRIMARY KEY (id);


--
-- Name: pros pros_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pros
    ADD CONSTRAINT pros_pkey PRIMARY KEY (id);


--
-- Name: record_access_grants record_access_grants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_access_grants
    ADD CONSTRAINT record_access_grants_pkey PRIMARY KEY (id);


--
-- Name: reviews reviews_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pkey PRIMARY KEY (booking_id);


--
-- Name: services services_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.services
    ADD CONSTRAINT services_pkey PRIMARY KEY (id);


--
-- Name: staff_permissions staff_permissions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_permissions
    ADD CONSTRAINT staff_permissions_pkey PRIMARY KEY (profile_id, permission);


--
-- Name: subscriptions subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pkey PRIMARY KEY (id);


--
-- Name: vital_signs vital_signs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vital_signs
    ADD CONSTRAINT vital_signs_pkey PRIMARY KEY (id);


--
-- Name: wallet_transactions wallet_transactions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_pkey PRIMARY KEY (id);


--
-- Name: wallets wallets_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_pkey PRIMARY KEY (owner_id);


--
-- Name: withdrawals withdrawals_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawals
    ADD CONSTRAINT withdrawals_pkey PRIMARY KEY (id);


--
-- Name: audit_events_actor_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX audit_events_actor_idx ON audit.events USING btree (actor_id, occurred_at DESC);


--
-- Name: audit_events_entity_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX audit_events_entity_idx ON audit.events USING btree (entity, entity_id);


--
-- Name: audit_events_patient_idx; Type: INDEX; Schema: audit; Owner: -
--

CREATE INDEX audit_events_patient_idx ON audit.events USING btree (patient_id, occurred_at DESC) WHERE (patient_id IS NOT NULL);


--
-- Name: availability_exceptions_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX availability_exceptions_pro_idx ON public.availability_exceptions USING gist (pro_id, period);


--
-- Name: availability_rules_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX availability_rules_pro_idx ON public.availability_rules USING btree (pro_id, weekday);


--
-- Name: bookings_booked_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_booked_by_idx ON public.bookings USING btree (booked_by, scheduled_at DESC);


--
-- Name: bookings_contract_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_contract_idx ON public.bookings USING btree (contract_id);


--
-- Name: bookings_open_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_open_idx ON public.bookings USING btree (status, scheduled_at) WHERE (status = ANY (ARRAY['pending'::public.booking_status, 'accepted'::public.booking_status]));


--
-- Name: bookings_patient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_patient_idx ON public.bookings USING btree (patient_id);


--
-- Name: bookings_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_pro_idx ON public.bookings USING btree (pro_id, status, scheduled_at);


--
-- Name: bookings_service_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX bookings_service_idx ON public.bookings USING btree (service_id);


--
-- Name: care_logs_booking_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX care_logs_booking_pro_idx ON public.care_logs USING btree (pro_id, created_at DESC);


--
-- Name: care_logs_patient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX care_logs_patient_idx ON public.care_logs USING btree (patient_id, created_at DESC);


--
-- Name: care_logs_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX care_logs_pro_idx ON public.care_logs USING btree (pro_id);


--
-- Name: complaints_assigned_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX complaints_assigned_idx ON public.complaints USING btree (assigned_to);


--
-- Name: complaints_booking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX complaints_booking_idx ON public.complaints USING btree (booking_id);


--
-- Name: complaints_opened_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX complaints_opened_by_idx ON public.complaints USING btree (opened_by, created_at DESC);


--
-- Name: complaints_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX complaints_pro_idx ON public.complaints USING btree (pro_id);


--
-- Name: complaints_queue_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX complaints_queue_idx ON public.complaints USING btree (status, priority, created_at) WHERE (status = ANY (ARRAY['open'::public.complaint_status, 'in_review'::public.complaint_status]));


--
-- Name: contracts_booked_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contracts_booked_by_idx ON public.contracts USING btree (booked_by);


--
-- Name: contracts_patient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contracts_patient_idx ON public.contracts USING btree (patient_id);


--
-- Name: contracts_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX contracts_pro_idx ON public.contracts USING btree (pro_id, status);


--
-- Name: medical_documents_booking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medical_documents_booking_idx ON public.medical_documents USING btree (booking_id);


--
-- Name: medical_documents_patient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medical_documents_patient_idx ON public.medical_documents USING btree (patient_id, created_at DESC) WHERE (deleted_at IS NULL);


--
-- Name: medical_documents_uploaded_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medical_documents_uploaded_by_idx ON public.medical_documents USING btree (uploaded_by);


--
-- Name: medical_records_updated_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX medical_records_updated_by_idx ON public.medical_records USING btree (updated_by);


--
-- Name: notifications_booking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_booking_idx ON public.notifications USING btree (booking_id);


--
-- Name: notifications_unread_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_unread_idx ON public.notifications USING btree (user_id) WHERE (read_at IS NULL);


--
-- Name: notifications_user_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX notifications_user_idx ON public.notifications USING btree (user_id, created_at DESC);


--
-- Name: patient_members_active_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX patient_members_active_idx ON public.patient_members USING btree (patient_id, member_id) WHERE (revoked_at IS NULL);


--
-- Name: patient_members_invited_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX patient_members_invited_by_idx ON public.patient_members USING btree (invited_by);


--
-- Name: patient_members_member_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX patient_members_member_idx ON public.patient_members USING btree (member_id) WHERE (revoked_at IS NULL);


--
-- Name: patients_owner_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX patients_owner_idx ON public.patients USING btree (owner_id);


--
-- Name: payments_booking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_booking_idx ON public.payments USING btree (booking_id);


--
-- Name: payments_payer_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_payer_idx ON public.payments USING btree (payer_id, created_at DESC);


--
-- Name: payments_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX payments_status_idx ON public.payments USING btree (status, created_at) WHERE (status = 'pending'::public.payment_status);


--
-- Name: pharmacies_commune_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pharmacies_commune_idx ON public.pharmacies USING btree (commune) WHERE active;


--
-- Name: pharmacies_on_duty_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pharmacies_on_duty_idx ON public.pharmacies USING btree (on_duty_until) WHERE (active AND (on_duty_until IS NOT NULL));


--
-- Name: pro_cancellations_booking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_cancellations_booking_idx ON public.pro_cancellations USING btree (booking_id);


--
-- Name: pro_cancellations_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_cancellations_pro_idx ON public.pro_cancellations USING btree (pro_id, created_at DESC);


--
-- Name: pro_documents_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_documents_pro_idx ON public.pro_documents USING btree (pro_id);


--
-- Name: pro_services_service_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pro_services_service_idx ON public.pro_services USING btree (service_id);


--
-- Name: pros_referred_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pros_referred_by_idx ON public.pros USING btree (referred_by);


--
-- Name: pros_search_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX pros_search_idx ON public.pros USING gin (communes) WHERE (verification_status = 'verified'::public.verification_status);


--
-- Name: record_access_grants_booking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX record_access_grants_booking_idx ON public.record_access_grants USING btree (booking_id) WHERE (source = 'booking'::text);


--
-- Name: record_access_grants_lookup_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX record_access_grants_lookup_idx ON public.record_access_grants USING btree (grantee_id, patient_id) WHERE (revoked_at IS NULL);


--
-- Name: record_access_grants_patient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX record_access_grants_patient_idx ON public.record_access_grants USING btree (patient_id, created_at DESC);


--
-- Name: reviews_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX reviews_pro_idx ON public.reviews USING btree (pro_id);


--
-- Name: staff_permissions_granted_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX staff_permissions_granted_by_idx ON public.staff_permissions USING btree (granted_by);


--
-- Name: subscriptions_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX subscriptions_pro_idx ON public.subscriptions USING btree (pro_id, ends_at DESC);


--
-- Name: vital_signs_booking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vital_signs_booking_idx ON public.vital_signs USING btree (booking_id);


--
-- Name: vital_signs_patient_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vital_signs_patient_idx ON public.vital_signs USING btree (patient_id, kind, measured_at DESC);


--
-- Name: vital_signs_recorded_by_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX vital_signs_recorded_by_idx ON public.vital_signs USING btree (recorded_by);


--
-- Name: wallet_transactions_booking_fk_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wallet_transactions_booking_fk_idx ON public.wallet_transactions USING btree (booking_id);


--
-- Name: wallet_transactions_booking_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wallet_transactions_booking_idx ON public.wallet_transactions USING btree (kind, booking_id) WHERE (booking_id IS NOT NULL);


--
-- Name: wallet_transactions_owner_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX wallet_transactions_owner_idx ON public.wallet_transactions USING btree (owner_id, created_at DESC);


--
-- Name: wallet_transactions_ref_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX wallet_transactions_ref_idx ON public.wallet_transactions USING btree (kind, external_ref) WHERE (external_ref IS NOT NULL);


--
-- Name: withdrawals_pro_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX withdrawals_pro_idx ON public.withdrawals USING btree (pro_id, created_at DESC);


--
-- Name: withdrawals_status_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX withdrawals_status_idx ON public.withdrawals USING btree (status, created_at) WHERE (status = 'pending'::text);


--
-- Name: events events_append_only; Type: TRIGGER; Schema: audit; Owner: -
--

CREATE TRIGGER events_append_only BEFORE DELETE OR UPDATE ON audit.events FOR EACH ROW EXECUTE FUNCTION audit.forbid_change();


--
-- Name: events events_no_truncate; Type: TRIGGER; Schema: audit; Owner: -
--

CREATE TRIGGER events_no_truncate BEFORE TRUNCATE ON audit.events FOR EACH STATEMENT EXECUTE FUNCTION audit.forbid_change();


--
-- Name: bookings bookings_contract_fill; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_contract_fill AFTER INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.contract_fill();


--
-- Name: bookings bookings_notify_insert; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_notify_insert AFTER INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.on_booking_insert_notify();


--
-- Name: bookings bookings_notify_update; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_notify_update AFTER UPDATE OF status, paid_at ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.on_booking_update_notify();


--
-- Name: bookings bookings_price; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_price BEFORE INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.price_booking();


--
-- Name: bookings bookings_price_zz_availability; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_price_zz_availability BEFORE INSERT ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.check_availability();


--
-- Name: bookings bookings_sync_grant; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER bookings_sync_grant AFTER INSERT OR UPDATE OF status ON public.bookings FOR EACH ROW EXECUTE FUNCTION private.sync_booking_grant();


--
-- Name: care_logs care_logs_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER care_logs_audit AFTER INSERT OR DELETE OR UPDATE ON public.care_logs FOR EACH ROW EXECUTE FUNCTION audit.log_change('phi', '', 'booking_id');


--
-- Name: care_logs care_logs_close; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER care_logs_close AFTER INSERT ON public.care_logs FOR EACH ROW EXECUTE FUNCTION private.on_care_log();


--
-- Name: care_logs care_logs_fill; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER care_logs_fill BEFORE INSERT ON public.care_logs FOR EACH ROW EXECUTE FUNCTION private.care_log_fill();


--
-- Name: care_logs care_logs_vitals; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER care_logs_vitals AFTER INSERT ON public.care_logs FOR EACH ROW EXECUTE FUNCTION private.care_log_vitals();


--
-- Name: complaints complaints_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER complaints_audit AFTER INSERT OR UPDATE ON public.complaints FOR EACH ROW EXECUTE FUNCTION audit.log_change('full');


--
-- Name: medical_documents medical_documents_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER medical_documents_audit AFTER INSERT OR DELETE OR UPDATE ON public.medical_documents FOR EACH ROW EXECUTE FUNCTION audit.log_change('phi', 'patient_id');


--
-- Name: medical_records medical_records_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER medical_records_audit AFTER INSERT OR DELETE OR UPDATE ON public.medical_records FOR EACH ROW EXECUTE FUNCTION audit.log_change('phi', 'patient_id', 'patient_id');


--
-- Name: medical_records medical_records_touch; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER medical_records_touch BEFORE UPDATE ON public.medical_records FOR EACH ROW EXECUTE FUNCTION private.touch_medical_record();


--
-- Name: patient_members patient_members_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER patient_members_audit AFTER INSERT OR DELETE OR UPDATE ON public.patient_members FOR EACH ROW EXECUTE FUNCTION audit.log_change('full', 'patient_id');


--
-- Name: patients patients_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER patients_audit AFTER INSERT OR DELETE OR UPDATE ON public.patients FOR EACH ROW EXECUTE FUNCTION audit.log_change('phi', 'id');


--
-- Name: patients patients_sync_medical_record; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER patients_sync_medical_record AFTER INSERT OR UPDATE OF allergies, treatments, history ON public.patients FOR EACH ROW EXECUTE FUNCTION private.sync_medical_record_from_patient();


--
-- Name: payments payments_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER payments_audit AFTER INSERT OR UPDATE ON public.payments FOR EACH ROW EXECUTE FUNCTION audit.log_change('full');


--
-- Name: platform_settings platform_settings_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER platform_settings_audit AFTER INSERT OR DELETE OR UPDATE ON public.platform_settings FOR EACH ROW EXECUTE FUNCTION audit.log_change('full', '', 'key');


--
-- Name: pro_cancellations pro_cancellations_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_cancellations_notify AFTER INSERT ON public.pro_cancellations FOR EACH ROW EXECUTE FUNCTION private.on_pro_cancellation_notify();


--
-- Name: pro_documents pro_documents_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_documents_audit AFTER INSERT OR DELETE ON public.pro_documents FOR EACH ROW EXECUTE FUNCTION audit.log_change('full');


--
-- Name: pro_services pro_services_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_services_audit AFTER INSERT OR DELETE OR UPDATE ON public.pro_services FOR EACH ROW EXECUTE FUNCTION audit.log_change('full', '', 'pro_id');


--
-- Name: pro_services pro_services_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_services_check BEFORE INSERT OR UPDATE ON public.pro_services FOR EACH ROW EXECUTE FUNCTION private.check_pro_service();


--
-- Name: pro_services pro_services_price_range; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pro_services_price_range BEFORE INSERT OR UPDATE OF price, service_id ON public.pro_services FOR EACH ROW EXECUTE FUNCTION private.check_pro_service_price();


--
-- Name: profiles profiles_notify_name; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER profiles_notify_name AFTER UPDATE OF full_name ON public.profiles FOR EACH ROW EXECUTE FUNCTION private.on_profile_name_notify();


--
-- Name: profiles profiles_role_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER profiles_role_audit AFTER UPDATE OF role ON public.profiles FOR EACH ROW EXECUTE FUNCTION audit.log_change('full');


--
-- Name: pros pros_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pros_audit AFTER UPDATE OF verification_status, rejection_reason, premium_until ON public.pros FOR EACH ROW EXECUTE FUNCTION audit.log_change('full');


--
-- Name: pros pros_check_referral; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pros_check_referral BEFORE INSERT ON public.pros FOR EACH ROW EXECUTE FUNCTION private.check_referral();


--
-- Name: pros pros_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER pros_notify AFTER INSERT OR UPDATE OF verification_status ON public.pros FOR EACH ROW EXECUTE FUNCTION private.on_pro_notify();


--
-- Name: record_access_grants record_access_grants_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER record_access_grants_audit AFTER INSERT OR DELETE OR UPDATE ON public.record_access_grants FOR EACH ROW EXECUTE FUNCTION audit.log_change('full', 'patient_id');


--
-- Name: reviews reviews_moderation_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reviews_moderation_audit AFTER UPDATE OF hidden_at ON public.reviews FOR EACH ROW EXECUTE FUNCTION audit.log_change('full', '', 'booking_id');


--
-- Name: reviews reviews_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reviews_notify AFTER INSERT ON public.reviews FOR EACH ROW EXECUTE FUNCTION private.on_review_notify();


--
-- Name: reviews reviews_rating; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER reviews_rating AFTER INSERT ON public.reviews FOR EACH ROW EXECUTE FUNCTION private.on_review();


--
-- Name: staff_permissions staff_permissions_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER staff_permissions_audit AFTER INSERT OR DELETE OR UPDATE ON public.staff_permissions FOR EACH ROW EXECUTE FUNCTION audit.log_change('full', '', 'profile_id');


--
-- Name: subscriptions subscriptions_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER subscriptions_audit AFTER INSERT ON public.subscriptions FOR EACH ROW EXECUTE FUNCTION audit.log_change('full');


--
-- Name: vital_signs vital_signs_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER vital_signs_audit AFTER INSERT OR DELETE OR UPDATE ON public.vital_signs FOR EACH ROW EXECUTE FUNCTION audit.log_change('phi', 'patient_id');


--
-- Name: vital_signs vital_signs_check; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER vital_signs_check BEFORE INSERT OR UPDATE ON public.vital_signs FOR EACH ROW EXECUTE FUNCTION private.check_vital_sign();


--
-- Name: wallet_transactions wallet_transactions_notify; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER wallet_transactions_notify AFTER INSERT ON public.wallet_transactions FOR EACH ROW EXECUTE FUNCTION private.on_wallet_tx_notify();


--
-- Name: withdrawals withdrawals_audit; Type: TRIGGER; Schema: public; Owner: -
--

CREATE TRIGGER withdrawals_audit AFTER INSERT OR UPDATE ON public.withdrawals FOR EACH ROW EXECUTE FUNCTION audit.log_change('full');


--
-- Name: availability_exceptions availability_exceptions_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_exceptions
    ADD CONSTRAINT availability_exceptions_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id) ON DELETE CASCADE;


--
-- Name: availability_rules availability_rules_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.availability_rules
    ADD CONSTRAINT availability_rules_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_booked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_booked_by_fkey FOREIGN KEY (booked_by) REFERENCES public.profiles(id);


--
-- Name: bookings bookings_contract_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_contract_id_fkey FOREIGN KEY (contract_id) REFERENCES public.contracts(id) ON DELETE CASCADE;


--
-- Name: bookings bookings_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id);


--
-- Name: bookings bookings_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id);


--
-- Name: bookings bookings_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.bookings
    ADD CONSTRAINT bookings_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.services(id);


--
-- Name: care_logs care_logs_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.care_logs
    ADD CONSTRAINT care_logs_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE;


--
-- Name: care_logs care_logs_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.care_logs
    ADD CONSTRAINT care_logs_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: care_logs care_logs_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.care_logs
    ADD CONSTRAINT care_logs_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id);


--
-- Name: complaints complaints_assigned_to_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: complaints complaints_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE SET NULL;


--
-- Name: complaints complaints_opened_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_opened_by_fkey FOREIGN KEY (opened_by) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: complaints complaints_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.complaints
    ADD CONSTRAINT complaints_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id) ON DELETE SET NULL;


--
-- Name: contracts contracts_booked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_booked_by_fkey FOREIGN KEY (booked_by) REFERENCES public.profiles(id);


--
-- Name: contracts contracts_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: contracts contracts_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id);


--
-- Name: contracts contracts_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.contracts
    ADD CONSTRAINT contracts_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.services(id);


--
-- Name: medical_documents medical_documents_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE SET NULL;


--
-- Name: medical_documents medical_documents_deleted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_deleted_by_fkey FOREIGN KEY (deleted_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: medical_documents medical_documents_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: medical_documents medical_documents_uploaded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_documents
    ADD CONSTRAINT medical_documents_uploaded_by_fkey FOREIGN KEY (uploaded_by) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: medical_records medical_records_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_records
    ADD CONSTRAINT medical_records_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: medical_records medical_records_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.medical_records
    ADD CONSTRAINT medical_records_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: notifications notifications_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE;


--
-- Name: notifications notifications_user_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: patient_members patient_members_invited_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_members
    ADD CONSTRAINT patient_members_invited_by_fkey FOREIGN KEY (invited_by) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: patient_members patient_members_member_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_members
    ADD CONSTRAINT patient_members_member_id_fkey FOREIGN KEY (member_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: patient_members patient_members_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_members
    ADD CONSTRAINT patient_members_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: patient_members patient_members_revoked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patient_members
    ADD CONSTRAINT patient_members_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: patients patients_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.patients
    ADD CONSTRAINT patients_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: payments payments_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE SET NULL;


--
-- Name: payments payments_payer_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.payments
    ADD CONSTRAINT payments_payer_id_fkey FOREIGN KEY (payer_id) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: platform_settings platform_settings_updated_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.platform_settings
    ADD CONSTRAINT platform_settings_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: pro_cancellations pro_cancellations_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_cancellations
    ADD CONSTRAINT pro_cancellations_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: pro_cancellations pro_cancellations_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_cancellations
    ADD CONSTRAINT pro_cancellations_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id) ON DELETE CASCADE;


--
-- Name: pro_documents pro_documents_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_documents
    ADD CONSTRAINT pro_documents_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id) ON DELETE CASCADE;


--
-- Name: pro_services pro_services_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_services
    ADD CONSTRAINT pro_services_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id) ON DELETE CASCADE;


--
-- Name: pro_services pro_services_service_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pro_services
    ADD CONSTRAINT pro_services_service_id_fkey FOREIGN KEY (service_id) REFERENCES public.services(id);


--
-- Name: profiles profiles_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.profiles
    ADD CONSTRAINT profiles_id_fkey FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE;


--
-- Name: pros pros_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pros
    ADD CONSTRAINT pros_id_fkey FOREIGN KEY (id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: pros pros_referred_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.pros
    ADD CONSTRAINT pros_referred_by_fkey FOREIGN KEY (referred_by) REFERENCES public.pros(id);


--
-- Name: record_access_grants record_access_grants_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_access_grants
    ADD CONSTRAINT record_access_grants_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE;


--
-- Name: record_access_grants record_access_grants_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_access_grants
    ADD CONSTRAINT record_access_grants_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: record_access_grants record_access_grants_grantee_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_access_grants
    ADD CONSTRAINT record_access_grants_grantee_id_fkey FOREIGN KEY (grantee_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: record_access_grants record_access_grants_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_access_grants
    ADD CONSTRAINT record_access_grants_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: record_access_grants record_access_grants_revoked_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.record_access_grants
    ADD CONSTRAINT record_access_grants_revoked_by_fkey FOREIGN KEY (revoked_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: reviews reviews_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE CASCADE;


--
-- Name: reviews reviews_hidden_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_hidden_by_fkey FOREIGN KEY (hidden_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: reviews reviews_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.reviews
    ADD CONSTRAINT reviews_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id);


--
-- Name: staff_permissions staff_permissions_granted_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_permissions
    ADD CONSTRAINT staff_permissions_granted_by_fkey FOREIGN KEY (granted_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: staff_permissions staff_permissions_profile_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.staff_permissions
    ADD CONSTRAINT staff_permissions_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: subscriptions subscriptions_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.subscriptions
    ADD CONSTRAINT subscriptions_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id) ON DELETE CASCADE;


--
-- Name: vital_signs vital_signs_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vital_signs
    ADD CONSTRAINT vital_signs_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id) ON DELETE SET NULL;


--
-- Name: vital_signs vital_signs_patient_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vital_signs
    ADD CONSTRAINT vital_signs_patient_id_fkey FOREIGN KEY (patient_id) REFERENCES public.patients(id) ON DELETE CASCADE;


--
-- Name: vital_signs vital_signs_recorded_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.vital_signs
    ADD CONSTRAINT vital_signs_recorded_by_fkey FOREIGN KEY (recorded_by) REFERENCES public.profiles(id) ON DELETE RESTRICT;


--
-- Name: wallet_transactions wallet_transactions_booking_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_booking_id_fkey FOREIGN KEY (booking_id) REFERENCES public.bookings(id);


--
-- Name: wallet_transactions wallet_transactions_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallet_transactions
    ADD CONSTRAINT wallet_transactions_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: wallets wallets_owner_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.wallets
    ADD CONSTRAINT wallets_owner_id_fkey FOREIGN KEY (owner_id) REFERENCES public.profiles(id) ON DELETE CASCADE;


--
-- Name: withdrawals withdrawals_pro_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawals
    ADD CONSTRAINT withdrawals_pro_id_fkey FOREIGN KEY (pro_id) REFERENCES public.pros(id) ON DELETE CASCADE;


--
-- Name: withdrawals withdrawals_processed_by_fkey; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.withdrawals
    ADD CONSTRAINT withdrawals_processed_by_fkey FOREIGN KEY (processed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;


--
-- Name: availability_exceptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.availability_exceptions ENABLE ROW LEVEL SECURITY;

--
-- Name: availability_exceptions availability_exceptions_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY availability_exceptions_delete ON public.availability_exceptions FOR DELETE TO authenticated USING ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: availability_exceptions availability_exceptions_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY availability_exceptions_insert ON public.availability_exceptions FOR INSERT TO authenticated WITH CHECK ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: availability_exceptions availability_exceptions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY availability_exceptions_select ON public.availability_exceptions FOR SELECT TO authenticated USING (((pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('manage_bookings'::public.staff_permission) AS has_perm)));


--
-- Name: availability_rules; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.availability_rules ENABLE ROW LEVEL SECURITY;

--
-- Name: availability_rules availability_rules_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY availability_rules_delete ON public.availability_rules FOR DELETE TO authenticated USING ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: availability_rules availability_rules_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY availability_rules_insert ON public.availability_rules FOR INSERT TO authenticated WITH CHECK ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: availability_rules availability_rules_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY availability_rules_select ON public.availability_rules FOR SELECT TO authenticated USING (true);


--
-- Name: bookings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

--
-- Name: bookings bookings_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bookings_insert ON public.bookings FOR INSERT TO authenticated WITH CHECK (((booked_by = ( SELECT auth.uid() AS uid)) AND ( SELECT private.can_act_for(bookings.patient_id, 'book_care'::public.member_permission) AS can_act_for)));


--
-- Name: bookings bookings_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bookings_member ON public.bookings FOR SELECT TO authenticated USING ((( SELECT private.member_has(bookings.patient_id, 'view_reports'::public.member_permission) AS member_has) OR ( SELECT private.member_has(bookings.patient_id, 'book_care'::public.member_permission) AS member_has)));


--
-- Name: bookings bookings_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY bookings_select ON public.bookings FOR SELECT TO authenticated USING (((booked_by = ( SELECT auth.uid() AS uid)) OR (pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_any_perm('{manage_bookings,support,finance}'::public.staff_permission[]) AS has_any_perm)));


--
-- Name: care_logs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.care_logs ENABLE ROW LEVEL SECURITY;

--
-- Name: care_logs care_logs_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY care_logs_insert ON public.care_logs FOR INSERT TO authenticated WITH CHECK ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: care_logs care_logs_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY care_logs_select ON public.care_logs FOR SELECT TO authenticated USING (((pro_id = ( SELECT auth.uid() AS uid)) OR (EXISTS ( SELECT 1
   FROM public.bookings b
  WHERE ((b.id = care_logs.booking_id) AND ((b.booked_by = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_record_access(b.patient_id, 'reports'::public.record_scope) AS has_record_access)))))));


--
-- Name: complaints; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;

--
-- Name: complaints complaints_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY complaints_select ON public.complaints FOR SELECT TO authenticated USING (((opened_by = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('support'::public.staff_permission) AS has_perm)));


--
-- Name: contracts; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

--
-- Name: contracts contracts_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contracts_insert ON public.contracts FOR INSERT TO authenticated WITH CHECK ((booked_by = ( SELECT auth.uid() AS uid)));


--
-- Name: contracts contracts_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY contracts_select ON public.contracts FOR SELECT TO authenticated USING (((booked_by = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_any_perm('{manage_bookings,support}'::public.staff_permission[]) AS has_any_perm) OR (EXISTS ( SELECT 1
   FROM public.bookings b
  WHERE ((b.contract_id = contracts.id) AND (b.pro_id = ( SELECT auth.uid() AS uid)))))));


--
-- Name: medical_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medical_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: medical_documents medical_documents_hide; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medical_documents_hide ON public.medical_documents FOR UPDATE TO authenticated USING ((( SELECT private.can_act_for(medical_documents.patient_id, 'manage_records'::public.member_permission) AS can_act_for) OR (uploaded_by = ( SELECT auth.uid() AS uid)))) WITH CHECK ((deleted_by = ( SELECT auth.uid() AS uid)));


--
-- Name: medical_documents medical_documents_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medical_documents_insert ON public.medical_documents FOR INSERT TO authenticated WITH CHECK (((uploaded_by = ( SELECT auth.uid() AS uid)) AND (( SELECT private.can_act_for(medical_documents.patient_id, 'manage_records'::public.member_permission) AS can_act_for) OR ( SELECT private.has_record_access(medical_documents.patient_id, 'documents'::public.record_scope) AS has_record_access))));


--
-- Name: medical_documents medical_documents_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medical_documents_select ON public.medical_documents FOR SELECT TO authenticated USING ((( SELECT private.can_act_for(medical_documents.patient_id, 'view_records'::public.member_permission) AS can_act_for) OR ( SELECT private.member_has(medical_documents.patient_id, 'manage_records'::public.member_permission) AS member_has) OR (uploaded_by = ( SELECT auth.uid() AS uid))));


--
-- Name: medical_records; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.medical_records ENABLE ROW LEVEL SECURITY;

--
-- Name: medical_records medical_records_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medical_records_insert ON public.medical_records FOR INSERT TO authenticated WITH CHECK (( SELECT private.can_act_for(medical_records.patient_id, 'manage_records'::public.member_permission) AS can_act_for));


--
-- Name: medical_records medical_records_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medical_records_select ON public.medical_records FOR SELECT TO authenticated USING ((( SELECT private.can_act_for(medical_records.patient_id, 'view_records'::public.member_permission) AS can_act_for) OR ( SELECT private.member_has(medical_records.patient_id, 'manage_records'::public.member_permission) AS member_has)));


--
-- Name: medical_records medical_records_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY medical_records_update ON public.medical_records FOR UPDATE TO authenticated USING (( SELECT private.can_act_for(medical_records.patient_id, 'manage_records'::public.member_permission) AS can_act_for)) WITH CHECK (( SELECT private.can_act_for(medical_records.patient_id, 'manage_records'::public.member_permission) AS can_act_for));


--
-- Name: notifications; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

--
-- Name: notifications notifications_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_select ON public.notifications FOR SELECT TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: notifications notifications_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY notifications_update ON public.notifications FOR UPDATE TO authenticated USING ((user_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((user_id = ( SELECT auth.uid() AS uid)));


--
-- Name: patient_members; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patient_members ENABLE ROW LEVEL SECURITY;

--
-- Name: patient_members patient_members_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY patient_members_select ON public.patient_members FOR SELECT TO authenticated USING (((member_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.owns_patient(patient_members.patient_id) AS owns_patient)));


--
-- Name: patients; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.patients ENABLE ROW LEVEL SECURITY;

--
-- Name: patients patients_member; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY patients_member ON public.patients FOR SELECT TO authenticated USING (( SELECT private.is_member(patients.id) AS is_member));


--
-- Name: patients patients_owner; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY patients_owner ON public.patients TO authenticated USING ((owner_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((owner_id = ( SELECT auth.uid() AS uid)));


--
-- Name: patients patients_pro; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY patients_pro ON public.patients FOR SELECT TO authenticated USING (( SELECT private.treats_patient(patients.id) AS treats_patient));


--
-- Name: payments; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

--
-- Name: payments payments_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY payments_select ON public.payments FOR SELECT TO authenticated USING (((payer_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('finance'::public.staff_permission) AS has_perm)));


--
-- Name: pharmacies; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pharmacies ENABLE ROW LEVEL SECURITY;

--
-- Name: pharmacies pharmacies_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_insert ON public.pharmacies FOR INSERT TO authenticated WITH CHECK (( SELECT private.has_perm('manage_settings'::public.staff_permission) AS has_perm));


--
-- Name: pharmacies pharmacies_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_select ON public.pharmacies FOR SELECT TO anon, authenticated USING ((active OR ( SELECT private.has_perm('manage_settings'::public.staff_permission) AS has_perm)));


--
-- Name: pharmacies pharmacies_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pharmacies_update ON public.pharmacies FOR UPDATE TO authenticated USING (( SELECT private.has_perm('manage_settings'::public.staff_permission) AS has_perm)) WITH CHECK (( SELECT private.has_perm('manage_settings'::public.staff_permission) AS has_perm));


--
-- Name: platform_settings; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.platform_settings ENABLE ROW LEVEL SECURITY;

--
-- Name: platform_settings platform_settings_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY platform_settings_select ON public.platform_settings FOR SELECT TO authenticated USING (true);


--
-- Name: pro_cancellations; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_cancellations ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_cancellations pro_cancellations_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_cancellations_select ON public.pro_cancellations FOR SELECT TO authenticated USING (((pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_any_perm('{verify_pros,manage_bookings}'::public.staff_permission[]) AS has_any_perm)));


--
-- Name: pro_documents; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_documents ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_documents pro_documents_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_documents_delete ON public.pro_documents FOR DELETE TO authenticated USING ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: pro_documents pro_documents_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_documents_insert ON public.pro_documents FOR INSERT TO authenticated WITH CHECK ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: pro_documents pro_documents_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_documents_select ON public.pro_documents FOR SELECT TO authenticated USING (((pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('verify_pros'::public.staff_permission) AS has_perm)));


--
-- Name: pro_services; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pro_services ENABLE ROW LEVEL SECURITY;

--
-- Name: pro_services pro_services_delete; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_services_delete ON public.pro_services FOR DELETE TO authenticated USING ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: pro_services pro_services_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_services_insert ON public.pro_services FOR INSERT TO authenticated WITH CHECK ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: pro_services pro_services_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_services_select ON public.pro_services FOR SELECT TO authenticated USING (true);


--
-- Name: pro_services pro_services_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pro_services_update ON public.pro_services FOR UPDATE TO authenticated USING ((pro_id = ( SELECT auth.uid() AS uid))) WITH CHECK ((pro_id = ( SELECT auth.uid() AS uid)));


--
-- Name: profiles; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

--
-- Name: profiles profiles_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_select ON public.profiles FOR SELECT TO authenticated USING (((id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_any_perm('{support,verify_pros,finance,manage_staff}'::public.staff_permission[]) AS has_any_perm)));


--
-- Name: profiles profiles_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY profiles_update ON public.profiles FOR UPDATE TO authenticated USING ((id = ( SELECT auth.uid() AS uid))) WITH CHECK ((id = ( SELECT auth.uid() AS uid)));


--
-- Name: pros; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.pros ENABLE ROW LEVEL SECURITY;

--
-- Name: pros pros_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pros_insert ON public.pros FOR INSERT TO authenticated WITH CHECK (((id = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM public.profiles pr
  WHERE ((pr.id = ( SELECT auth.uid() AS uid)) AND (pr.role = 'pro'::public.user_role))))));


--
-- Name: pros pros_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pros_select ON public.pros FOR SELECT TO authenticated USING (((verification_status = 'verified'::public.verification_status) OR (id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin)));


--
-- Name: pros pros_update; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY pros_update ON public.pros FOR UPDATE TO authenticated USING ((id = ( SELECT auth.uid() AS uid))) WITH CHECK ((id = ( SELECT auth.uid() AS uid)));


--
-- Name: record_access_grants; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.record_access_grants ENABLE ROW LEVEL SECURITY;

--
-- Name: record_access_grants record_access_grants_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY record_access_grants_select ON public.record_access_grants FOR SELECT TO authenticated USING (((grantee_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.owns_patient(record_access_grants.patient_id) AS owns_patient) OR ( SELECT private.has_perm('audit_read'::public.staff_permission) AS has_perm)));


--
-- Name: reviews; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.reviews ENABLE ROW LEVEL SECURITY;

--
-- Name: reviews reviews_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reviews_insert ON public.reviews FOR INSERT TO authenticated WITH CHECK ((EXISTS ( SELECT 1
   FROM public.bookings b
  WHERE ((b.id = reviews.booking_id) AND (b.booked_by = ( SELECT auth.uid() AS uid)) AND (b.pro_id = reviews.pro_id) AND (b.status = 'done'::public.booking_status)))));


--
-- Name: reviews reviews_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY reviews_select ON public.reviews FOR SELECT TO authenticated USING (((hidden_at IS NULL) OR (pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('moderate'::public.staff_permission) AS has_perm)));


--
-- Name: services; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.services ENABLE ROW LEVEL SECURITY;

--
-- Name: services services_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY services_select ON public.services FOR SELECT TO anon, authenticated USING (active);


--
-- Name: staff_permissions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.staff_permissions ENABLE ROW LEVEL SECURITY;

--
-- Name: staff_permissions staff_permissions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY staff_permissions_select ON public.staff_permissions FOR SELECT TO authenticated USING (((profile_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('manage_staff'::public.staff_permission) AS has_perm)));


--
-- Name: subscriptions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;

--
-- Name: subscriptions subscriptions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY subscriptions_select ON public.subscriptions FOR SELECT TO authenticated USING (((pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('finance'::public.staff_permission) AS has_perm)));


--
-- Name: vital_signs; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.vital_signs ENABLE ROW LEVEL SECURITY;

--
-- Name: vital_signs vital_signs_flag; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vital_signs_flag ON public.vital_signs FOR UPDATE TO authenticated USING ((recorded_by = ( SELECT auth.uid() AS uid))) WITH CHECK ((recorded_by = ( SELECT auth.uid() AS uid)));


--
-- Name: vital_signs vital_signs_insert; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vital_signs_insert ON public.vital_signs FOR INSERT TO authenticated WITH CHECK (((recorded_by = ( SELECT auth.uid() AS uid)) AND (( SELECT private.can_act_for(vital_signs.patient_id, 'manage_records'::public.member_permission) AS can_act_for) OR ( SELECT private.has_record_access(vital_signs.patient_id, 'vitals'::public.record_scope) AS has_record_access))));


--
-- Name: vital_signs vital_signs_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY vital_signs_select ON public.vital_signs FOR SELECT TO authenticated USING ((( SELECT private.can_act_for(vital_signs.patient_id, 'view_records'::public.member_permission) AS can_act_for) OR (recorded_by = ( SELECT auth.uid() AS uid))));


--
-- Name: wallet_transactions; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.wallet_transactions ENABLE ROW LEVEL SECURITY;

--
-- Name: wallet_transactions wallet_transactions_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallet_transactions_select ON public.wallet_transactions FOR SELECT TO authenticated USING (((owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('finance'::public.staff_permission) AS has_perm)));


--
-- Name: wallets; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.wallets ENABLE ROW LEVEL SECURITY;

--
-- Name: wallets wallets_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY wallets_select ON public.wallets FOR SELECT TO authenticated USING (((owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('finance'::public.staff_permission) AS has_perm)));


--
-- Name: withdrawals; Type: ROW SECURITY; Schema: public; Owner: -
--

ALTER TABLE public.withdrawals ENABLE ROW LEVEL SECURITY;

--
-- Name: withdrawals withdrawals_select; Type: POLICY; Schema: public; Owner: -
--

CREATE POLICY withdrawals_select ON public.withdrawals FOR SELECT TO authenticated USING (((pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.has_perm('finance'::public.staff_permission) AS has_perm)));


--
-- Name: SCHEMA private; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA private TO authenticated;


--
-- Name: SCHEMA public; Type: ACL; Schema: -; Owner: -
--

GRANT USAGE ON SCHEMA public TO anon;
GRANT USAGE ON SCHEMA public TO authenticated;
GRANT USAGE ON SCHEMA public TO service_role;


--
-- Name: FUNCTION "current_role"(); Type: ACL; Schema: audit; Owner: -
--

REVOKE ALL ON FUNCTION audit."current_role"() FROM PUBLIC;


--
-- Name: FUNCTION forbid_change(); Type: ACL; Schema: audit; Owner: -
--

REVOKE ALL ON FUNCTION audit.forbid_change() FROM PUBLIC;


--
-- Name: FUNCTION log(p_action text, p_entity text, p_entity_id text, p_patient uuid, p_reason text, p_data jsonb); Type: ACL; Schema: audit; Owner: -
--

REVOKE ALL ON FUNCTION audit.log(p_action text, p_entity text, p_entity_id text, p_patient uuid, p_reason text, p_data jsonb) FROM PUBLIC;


--
-- Name: FUNCTION log_change(); Type: ACL; Schema: audit; Owner: -
--

REVOKE ALL ON FUNCTION audit.log_change() FROM PUBLIC;


--
-- Name: FUNCTION can_act_for(p_patient uuid, p_perm public.member_permission); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.can_act_for(p_patient uuid, p_perm public.member_permission) FROM PUBLIC;
GRANT ALL ON FUNCTION private.can_act_for(p_patient uuid, p_perm public.member_permission) TO authenticated;


--
-- Name: FUNCTION care_log_fill(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.care_log_fill() FROM PUBLIC;


--
-- Name: FUNCTION care_log_vitals(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.care_log_vitals() FROM PUBLIC;


--
-- Name: FUNCTION check_availability(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.check_availability() FROM PUBLIC;


--
-- Name: FUNCTION check_pro_service(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.check_pro_service() FROM PUBLIC;


--
-- Name: FUNCTION check_pro_service_price(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.check_pro_service_price() FROM PUBLIC;


--
-- Name: FUNCTION check_referral(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.check_referral() FROM PUBLIC;


--
-- Name: FUNCTION check_vital_sign(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.check_vital_sign() FROM PUBLIC;


--
-- Name: FUNCTION contract_fill(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.contract_fill() FROM PUBLIC;


--
-- Name: FUNCTION fcfa(p integer); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.fcfa(p integer) FROM PUBLIC;


--
-- Name: TABLE bookings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.bookings TO service_role;
GRANT SELECT ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.booked_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(booked_by) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.patient_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(patient_id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.pro_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(pro_id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.service_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(service_id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.commune; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(commune) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.address; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(address) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.scheduled_at; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(scheduled_at) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.has_prescription; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(has_prescription) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.note; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(note) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.contract_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(contract_id) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.session_index; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(session_index) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.location_lat; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(location_lat) ON TABLE public.bookings TO authenticated;


--
-- Name: COLUMN bookings.location_lng; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(location_lng) ON TABLE public.bookings TO authenticated;


--
-- Name: FUNCTION first_of_group(b public.bookings, p_status public.booking_status); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.first_of_group(b public.bookings, p_status public.booking_status) FROM PUBLIC;


--
-- Name: FUNCTION handle_new_user(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.handle_new_user() FROM PUBLIC;


--
-- Name: FUNCTION has_any_perm(p_perms public.staff_permission[]); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.has_any_perm(p_perms public.staff_permission[]) FROM PUBLIC;
GRANT ALL ON FUNCTION private.has_any_perm(p_perms public.staff_permission[]) TO authenticated;


--
-- Name: FUNCTION has_perm(p_perm public.staff_permission); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.has_perm(p_perm public.staff_permission) FROM PUBLIC;
GRANT ALL ON FUNCTION private.has_perm(p_perm public.staff_permission) TO authenticated;


--
-- Name: FUNCTION has_record_access(p_patient uuid, p_scope public.record_scope); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.has_record_access(p_patient uuid, p_scope public.record_scope) FROM PUBLIC;
GRANT ALL ON FUNCTION private.has_record_access(p_patient uuid, p_scope public.record_scope) TO authenticated;


--
-- Name: FUNCTION is_admin(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.is_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION private.is_admin() TO authenticated;


--
-- Name: FUNCTION is_member(p_patient uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.is_member(p_patient uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION private.is_member(p_patient uuid) TO authenticated;


--
-- Name: FUNCTION late_fee(b public.bookings); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.late_fee(b public.bookings) FROM PUBLIC;


--
-- Name: FUNCTION member_has(p_patient uuid, p_perm public.member_permission); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.member_has(p_patient uuid, p_perm public.member_permission) FROM PUBLIC;
GRANT ALL ON FUNCTION private.member_has(p_patient uuid, p_perm public.member_permission) TO authenticated;


--
-- Name: FUNCTION notify(p_user uuid, p_title text, p_body text, p_booking uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.notify(p_user uuid, p_title text, p_body text, p_booking uuid) FROM PUBLIC;


--
-- Name: FUNCTION notify_admins(p_title text, p_body text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.notify_admins(p_title text, p_body text) FROM PUBLIC;


--
-- Name: FUNCTION num(p text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.num(p text) FROM PUBLIC;


--
-- Name: FUNCTION on_booking_insert_notify(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_booking_insert_notify() FROM PUBLIC;


--
-- Name: FUNCTION on_booking_update_notify(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_booking_update_notify() FROM PUBLIC;


--
-- Name: FUNCTION on_care_log(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_care_log() FROM PUBLIC;


--
-- Name: FUNCTION on_pro_cancellation_notify(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_pro_cancellation_notify() FROM PUBLIC;


--
-- Name: FUNCTION on_pro_notify(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_pro_notify() FROM PUBLIC;


--
-- Name: FUNCTION on_profile_name_notify(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_profile_name_notify() FROM PUBLIC;


--
-- Name: FUNCTION on_review(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_review() FROM PUBLIC;


--
-- Name: FUNCTION on_review_notify(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_review_notify() FROM PUBLIC;


--
-- Name: FUNCTION on_wallet_tx_notify(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.on_wallet_tx_notify() FROM PUBLIC;


--
-- Name: FUNCTION owns_patient(p_patient uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.owns_patient(p_patient uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION private.owns_patient(p_patient uuid) TO authenticated;


--
-- Name: FUNCTION patient_name(p uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.patient_name(p uuid) FROM PUBLIC;


--
-- Name: FUNCTION payable_group(p_booking uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.payable_group(p_booking uuid) FROM PUBLIC;


--
-- Name: FUNCTION payment_deadline(b public.bookings); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.payment_deadline(b public.bookings) FROM PUBLIC;


--
-- Name: FUNCTION price_booking(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.price_booking() FROM PUBLIC;


--
-- Name: FUNCTION pro_name(p uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.pro_name(p uuid) FROM PUBLIC;


--
-- Name: FUNCTION refund_booking(p_booking uuid, p_fee integer); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.refund_booking(p_booking uuid, p_fee integer) FROM PUBLIC;


--
-- Name: FUNCTION require_admin(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.require_admin() FROM PUBLIC;
GRANT ALL ON FUNCTION private.require_admin() TO authenticated;


--
-- Name: FUNCTION require_perm(p_perm public.staff_permission); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.require_perm(p_perm public.staff_permission) FROM PUBLIC;


--
-- Name: FUNCTION required_docs(p_type public.pro_type); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.required_docs(p_type public.pro_type) FROM PUBLIC;
GRANT ALL ON FUNCTION private.required_docs(p_type public.pro_type) TO authenticated;


--
-- Name: FUNCTION response_deadline(b public.bookings); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.response_deadline(b public.bookings) FROM PUBLIC;


--
-- Name: FUNCTION service_name(p text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.service_name(p text) FROM PUBLIC;


--
-- Name: FUNCTION setting_num(p_key text, p_default numeric); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.setting_num(p_key text, p_default numeric) FROM PUBLIC;


--
-- Name: FUNCTION sync_booking_grant(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.sync_booking_grant() FROM PUBLIC;


--
-- Name: FUNCTION sync_medical_record_from_patient(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.sync_medical_record_from_patient() FROM PUBLIC;


--
-- Name: FUNCTION touch_medical_record(); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.touch_medical_record() FROM PUBLIC;


--
-- Name: FUNCTION treats_patient(p_patient uuid); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.treats_patient(p_patient uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION private.treats_patient(p_patient uuid) TO authenticated;


--
-- Name: FUNCTION try_uuid(p text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.try_uuid(p text) FROM PUBLIC;
GRANT ALL ON FUNCTION private.try_uuid(p text) TO authenticated;


--
-- Name: FUNCTION wallet_move(p_owner uuid, p_kind public.wallet_tx_kind, p_amount integer, p_booking uuid, p_ref text, p_label text); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.wallet_move(p_owner uuid, p_kind public.wallet_tx_kind, p_amount integer, p_booking uuid, p_ref text, p_label text) FROM PUBLIC;


--
-- Name: FUNCTION when_label(p timestamp with time zone); Type: ACL; Schema: private; Owner: -
--

REVOKE ALL ON FUNCTION private.when_label(p timestamp with time zone) FROM PUBLIC;


--
-- Name: FUNCTION add_patient_member(p_patient uuid, p_contact text, p_relation public.member_relation, p_permissions public.member_permission[], p_expires_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.add_patient_member(p_patient uuid, p_contact text, p_relation public.member_relation, p_permissions public.member_permission[], p_expires_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.add_patient_member(p_patient uuid, p_contact text, p_relation public.member_relation, p_permissions public.member_permission[], p_expires_at timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.add_patient_member(p_patient uuid, p_contact text, p_relation public.member_relation, p_permissions public.member_permission[], p_expires_at timestamp with time zone) TO service_role;


--
-- Name: FUNCTION admin_audit_events(p_patient uuid, p_actor uuid, p_entity text, p_since timestamp with time zone, p_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_audit_events(p_patient uuid, p_actor uuid, p_entity text, p_since timestamp with time zone, p_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_audit_events(p_patient uuid, p_actor uuid, p_entity text, p_since timestamp with time zone, p_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.admin_audit_events(p_patient uuid, p_actor uuid, p_entity text, p_since timestamp with time zone, p_limit integer) TO service_role;


--
-- Name: FUNCTION admin_break_glass(p_patient uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_break_glass(p_patient uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_break_glass(p_patient uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_break_glass(p_patient uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION admin_commission_report(p_from date, p_to date); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_commission_report(p_from date, p_to date) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_commission_report(p_from date, p_to date) TO authenticated;
GRANT ALL ON FUNCTION public.admin_commission_report(p_from date, p_to date) TO service_role;


--
-- Name: FUNCTION admin_hide_review(p_booking uuid, p_hide boolean, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_hide_review(p_booking uuid, p_hide boolean, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_hide_review(p_booking uuid, p_hide boolean, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_hide_review(p_booking uuid, p_hide boolean, p_reason text) TO service_role;


--
-- Name: FUNCTION admin_reject_pro(p_pro uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_reject_pro(p_pro uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_reject_pro(p_pro uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_reject_pro(p_pro uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION admin_reliability_alerts(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_reliability_alerts() FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_reliability_alerts() TO authenticated;
GRANT ALL ON FUNCTION public.admin_reliability_alerts() TO service_role;


--
-- Name: FUNCTION admin_set_staff_permission(p_profile uuid, p_perm public.staff_permission, p_grant boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_set_staff_permission(p_profile uuid, p_perm public.staff_permission, p_grant boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_set_staff_permission(p_profile uuid, p_perm public.staff_permission, p_grant boolean) TO authenticated;
GRANT ALL ON FUNCTION public.admin_set_staff_permission(p_profile uuid, p_perm public.staff_permission, p_grant boolean) TO service_role;


--
-- Name: FUNCTION admin_settle_withdrawal(p_id uuid, p_sent boolean, p_ref text, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_settle_withdrawal(p_id uuid, p_sent boolean, p_ref text, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_settle_withdrawal(p_id uuid, p_sent boolean, p_ref text, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_settle_withdrawal(p_id uuid, p_sent boolean, p_ref text, p_reason text) TO service_role;


--
-- Name: FUNCTION admin_suspend_pro(p_pro uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_suspend_pro(p_pro uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_suspend_pro(p_pro uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.admin_suspend_pro(p_pro uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION admin_update_complaint(p_id uuid, p_status public.complaint_status, p_resolution text, p_refund integer, p_assign_to uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_update_complaint(p_id uuid, p_status public.complaint_status, p_resolution text, p_refund integer, p_assign_to uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_update_complaint(p_id uuid, p_status public.complaint_status, p_resolution text, p_refund integer, p_assign_to uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_update_complaint(p_id uuid, p_status public.complaint_status, p_resolution text, p_refund integer, p_assign_to uuid) TO service_role;


--
-- Name: FUNCTION admin_update_setting(p_key text, p_value jsonb); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_update_setting(p_key text, p_value jsonb) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_update_setting(p_key text, p_value jsonb) TO authenticated;
GRANT ALL ON FUNCTION public.admin_update_setting(p_key text, p_value jsonb) TO service_role;


--
-- Name: FUNCTION admin_verify_pro(p_pro uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.admin_verify_pro(p_pro uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.admin_verify_pro(p_pro uuid) TO authenticated;
GRANT ALL ON FUNCTION public.admin_verify_pro(p_pro uuid) TO service_role;


--
-- Name: FUNCTION bootstrap_staff(p_profile uuid, p_perms public.staff_permission[]); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.bootstrap_staff(p_profile uuid, p_perms public.staff_permission[]) FROM PUBLIC;
GRANT ALL ON FUNCTION public.bootstrap_staff(p_profile uuid, p_perms public.staff_permission[]) TO service_role;


--
-- Name: FUNCTION cancel_booking(p_booking uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.cancel_booking(p_booking uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.cancel_booking(p_booking uuid) TO authenticated;
GRANT ALL ON FUNCTION public.cancel_booking(p_booking uuid) TO service_role;


--
-- Name: FUNCTION confirm_payment(p_booking uuid, p_method text, p_ref text, p_amount integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.confirm_payment(p_booking uuid, p_method text, p_ref text, p_amount integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.confirm_payment(p_booking uuid, p_method text, p_ref text, p_amount integer) TO service_role;


--
-- Name: FUNCTION confirm_topup(p_owner uuid, p_amount integer, p_method text, p_ref text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.confirm_topup(p_owner uuid, p_amount integer, p_method text, p_ref text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.confirm_topup(p_owner uuid, p_amount integer, p_method text, p_ref text) TO service_role;


--
-- Name: FUNCTION expire_stale_bookings(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.expire_stale_bookings() FROM PUBLIC;
GRANT ALL ON FUNCTION public.expire_stale_bookings() TO service_role;


--
-- Name: FUNCTION get_patient_chart(p_patient uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.get_patient_chart(p_patient uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.get_patient_chart(p_patient uuid) TO authenticated;
GRANT ALL ON FUNCTION public.get_patient_chart(p_patient uuid) TO service_role;


--
-- Name: FUNCTION grant_record_access(p_patient uuid, p_pro uuid, p_scopes public.record_scope[], p_expires_at timestamp with time zone, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.grant_record_access(p_patient uuid, p_pro uuid, p_scopes public.record_scope[], p_expires_at timestamp with time zone, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.grant_record_access(p_patient uuid, p_pro uuid, p_scopes public.record_scope[], p_expires_at timestamp with time zone, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.grant_record_access(p_patient uuid, p_pro uuid, p_scopes public.record_scope[], p_expires_at timestamp with time zone, p_reason text) TO service_role;


--
-- Name: FUNCTION my_record_access_log(p_patient uuid, p_limit integer); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.my_record_access_log(p_patient uuid, p_limit integer) FROM PUBLIC;
GRANT ALL ON FUNCTION public.my_record_access_log(p_patient uuid, p_limit integer) TO authenticated;
GRANT ALL ON FUNCTION public.my_record_access_log(p_patient uuid, p_limit integer) TO service_role;


--
-- Name: FUNCTION open_complaint(p_booking uuid, p_category public.complaint_category, p_description text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.open_complaint(p_booking uuid, p_category public.complaint_category, p_description text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.open_complaint(p_booking uuid, p_category public.complaint_category, p_description text) TO authenticated;
GRANT ALL ON FUNCTION public.open_complaint(p_booking uuid, p_category public.complaint_category, p_description text) TO service_role;


--
-- Name: FUNCTION pay_booking_with_wallet(p_booking uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pay_booking_with_wallet(p_booking uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pay_booking_with_wallet(p_booking uuid) TO authenticated;
GRANT ALL ON FUNCTION public.pay_booking_with_wallet(p_booking uuid) TO service_role;


--
-- Name: FUNCTION pro_cancel_booking(p_booking uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.pro_cancel_booking(p_booking uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.pro_cancel_booking(p_booking uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.pro_cancel_booking(p_booking uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION request_withdrawal(p_amount integer, p_method text, p_phone text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.request_withdrawal(p_amount integer, p_method text, p_phone text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.request_withdrawal(p_amount integer, p_method text, p_phone text) TO authenticated;
GRANT ALL ON FUNCTION public.request_withdrawal(p_amount integer, p_method text, p_phone text) TO service_role;


--
-- Name: FUNCTION respond_booking(p_booking uuid, p_accept boolean); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.respond_booking(p_booking uuid, p_accept boolean) FROM PUBLIC;
GRANT ALL ON FUNCTION public.respond_booking(p_booking uuid, p_accept boolean) TO authenticated;
GRANT ALL ON FUNCTION public.respond_booking(p_booking uuid, p_accept boolean) TO service_role;


--
-- Name: FUNCTION resubmit_pro(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.resubmit_pro() FROM PUBLIC;
GRANT ALL ON FUNCTION public.resubmit_pro() TO authenticated;
GRANT ALL ON FUNCTION public.resubmit_pro() TO service_role;


--
-- Name: FUNCTION revoke_patient_member(p_member uuid); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revoke_patient_member(p_member uuid) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revoke_patient_member(p_member uuid) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_patient_member(p_member uuid) TO service_role;


--
-- Name: FUNCTION revoke_record_access(p_grant uuid, p_reason text); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.revoke_record_access(p_grant uuid, p_reason text) FROM PUBLIC;
GRANT ALL ON FUNCTION public.revoke_record_access(p_grant uuid, p_reason text) TO authenticated;
GRANT ALL ON FUNCTION public.revoke_record_access(p_grant uuid, p_reason text) TO service_role;


--
-- Name: FUNCTION search_pros(p_service text, p_commune text); Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON FUNCTION public.search_pros(p_service text, p_commune text) TO anon;
GRANT ALL ON FUNCTION public.search_pros(p_service text, p_commune text) TO authenticated;
GRANT ALL ON FUNCTION public.search_pros(p_service text, p_commune text) TO service_role;


--
-- Name: FUNCTION subscribe_premium(); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.subscribe_premium() FROM PUBLIC;
GRANT ALL ON FUNCTION public.subscribe_premium() TO authenticated;
GRANT ALL ON FUNCTION public.subscribe_premium() TO service_role;


--
-- Name: FUNCTION update_patient_member(p_member uuid, p_permissions public.member_permission[], p_expires_at timestamp with time zone); Type: ACL; Schema: public; Owner: -
--

REVOKE ALL ON FUNCTION public.update_patient_member(p_member uuid, p_permissions public.member_permission[], p_expires_at timestamp with time zone) FROM PUBLIC;
GRANT ALL ON FUNCTION public.update_patient_member(p_member uuid, p_permissions public.member_permission[], p_expires_at timestamp with time zone) TO authenticated;
GRANT ALL ON FUNCTION public.update_patient_member(p_member uuid, p_permissions public.member_permission[], p_expires_at timestamp with time zone) TO service_role;


--
-- Name: TABLE availability_exceptions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.availability_exceptions TO service_role;
GRANT SELECT,DELETE ON TABLE public.availability_exceptions TO authenticated;


--
-- Name: COLUMN availability_exceptions.pro_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(pro_id) ON TABLE public.availability_exceptions TO authenticated;


--
-- Name: COLUMN availability_exceptions.period; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(period) ON TABLE public.availability_exceptions TO authenticated;


--
-- Name: COLUMN availability_exceptions.kind; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(kind) ON TABLE public.availability_exceptions TO authenticated;


--
-- Name: COLUMN availability_exceptions.reason; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(reason) ON TABLE public.availability_exceptions TO authenticated;


--
-- Name: TABLE availability_rules; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.availability_rules TO service_role;
GRANT SELECT,DELETE ON TABLE public.availability_rules TO authenticated;


--
-- Name: COLUMN availability_rules.pro_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(pro_id) ON TABLE public.availability_rules TO authenticated;


--
-- Name: COLUMN availability_rules.weekday; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(weekday) ON TABLE public.availability_rules TO authenticated;


--
-- Name: COLUMN availability_rules.start_time; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(start_time) ON TABLE public.availability_rules TO authenticated;


--
-- Name: COLUMN availability_rules.end_time; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(end_time) ON TABLE public.availability_rules TO authenticated;


--
-- Name: TABLE care_logs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.care_logs TO service_role;
GRANT SELECT,INSERT ON TABLE public.care_logs TO authenticated;


--
-- Name: TABLE complaints; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.complaints TO service_role;
GRANT SELECT ON TABLE public.complaints TO authenticated;


--
-- Name: TABLE contracts; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.contracts TO anon;
GRANT ALL ON TABLE public.contracts TO authenticated;
GRANT ALL ON TABLE public.contracts TO service_role;


--
-- Name: TABLE medical_documents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.medical_documents TO service_role;
GRANT SELECT ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(id) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.patient_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(patient_id) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.kind; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(kind) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.title; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(title) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.storage_path; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(storage_path) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.mime_type; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(mime_type) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.size_bytes; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(size_bytes) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.document_date; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(document_date) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.booking_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(booking_id) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.uploaded_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(uploaded_by) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.deleted_at; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(deleted_at) ON TABLE public.medical_documents TO authenticated;


--
-- Name: COLUMN medical_documents.deleted_by; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(deleted_by) ON TABLE public.medical_documents TO authenticated;


--
-- Name: TABLE medical_records; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.medical_records TO service_role;
GRANT SELECT ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.patient_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(patient_id) ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.blood_group; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(blood_group),UPDATE(blood_group) ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.allergies; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(allergies),UPDATE(allergies) ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.chronic_conditions; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(chronic_conditions),UPDATE(chronic_conditions) ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.current_treatments; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(current_treatments),UPDATE(current_treatments) ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.history; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(history),UPDATE(history) ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.emergency_contact_name; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(emergency_contact_name),UPDATE(emergency_contact_name) ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.emergency_contact_phone; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(emergency_contact_phone),UPDATE(emergency_contact_phone) ON TABLE public.medical_records TO authenticated;


--
-- Name: COLUMN medical_records.primary_doctor; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(primary_doctor),UPDATE(primary_doctor) ON TABLE public.medical_records TO authenticated;


--
-- Name: TABLE notifications; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.notifications TO service_role;
GRANT SELECT ON TABLE public.notifications TO authenticated;


--
-- Name: COLUMN notifications.read_at; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(read_at) ON TABLE public.notifications TO authenticated;


--
-- Name: TABLE patient_members; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.patient_members TO service_role;
GRANT SELECT ON TABLE public.patient_members TO authenticated;


--
-- Name: TABLE patients; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.patients TO service_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.patients TO authenticated;


--
-- Name: TABLE payments; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.payments TO service_role;
GRANT SELECT ON TABLE public.payments TO authenticated;


--
-- Name: TABLE pharmacies; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pharmacies TO service_role;
GRANT SELECT ON TABLE public.pharmacies TO anon;
GRANT SELECT,INSERT,UPDATE ON TABLE public.pharmacies TO authenticated;


--
-- Name: TABLE platform_settings; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.platform_settings TO service_role;
GRANT SELECT ON TABLE public.platform_settings TO authenticated;


--
-- Name: TABLE pro_cancellations; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_cancellations TO anon;
GRANT ALL ON TABLE public.pro_cancellations TO authenticated;
GRANT ALL ON TABLE public.pro_cancellations TO service_role;


--
-- Name: TABLE pro_documents; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_documents TO service_role;
GRANT SELECT,INSERT,DELETE ON TABLE public.pro_documents TO authenticated;


--
-- Name: TABLE pro_services; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pro_services TO service_role;
GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.pro_services TO authenticated;


--
-- Name: TABLE profiles; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.profiles TO service_role;
GRANT SELECT ON TABLE public.profiles TO authenticated;


--
-- Name: COLUMN profiles.full_name; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(full_name) ON TABLE public.profiles TO authenticated;


--
-- Name: COLUMN profiles.commune; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(commune) ON TABLE public.profiles TO authenticated;


--
-- Name: TABLE pros; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.pros TO service_role;
GRANT SELECT ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(id) ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.display_name; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(display_name),UPDATE(display_name) ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.pro_type; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(pro_type) ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.bio; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(bio),UPDATE(bio) ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.years_experience; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(years_experience),UPDATE(years_experience) ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.communes; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(communes),UPDATE(communes) ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.night_available; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(night_available),UPDATE(night_available) ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.order_number; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(order_number) ON TABLE public.pros TO authenticated;


--
-- Name: COLUMN pros.referred_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(referred_by) ON TABLE public.pros TO authenticated;


--
-- Name: TABLE record_access_grants; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.record_access_grants TO service_role;
GRANT SELECT ON TABLE public.record_access_grants TO authenticated;


--
-- Name: TABLE reviews; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.reviews TO service_role;
GRANT SELECT,INSERT ON TABLE public.reviews TO authenticated;


--
-- Name: TABLE services; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.services TO service_role;
GRANT SELECT ON TABLE public.services TO anon;
GRANT SELECT ON TABLE public.services TO authenticated;


--
-- Name: TABLE staff_permissions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.staff_permissions TO service_role;
GRANT SELECT ON TABLE public.staff_permissions TO authenticated;


--
-- Name: TABLE subscriptions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.subscriptions TO service_role;
GRANT SELECT ON TABLE public.subscriptions TO authenticated;


--
-- Name: TABLE vital_signs; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.vital_signs TO service_role;
GRANT SELECT ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.patient_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(patient_id) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.kind; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(kind) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.value; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(value) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.value2; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(value2) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.unit; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(unit) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.measured_at; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(measured_at) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.booking_id; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(booking_id) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.recorded_by; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(recorded_by) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.note; Type: ACL; Schema: public; Owner: -
--

GRANT INSERT(note) ON TABLE public.vital_signs TO authenticated;


--
-- Name: COLUMN vital_signs.entered_in_error; Type: ACL; Schema: public; Owner: -
--

GRANT UPDATE(entered_in_error) ON TABLE public.vital_signs TO authenticated;


--
-- Name: TABLE wallet_transactions; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.wallet_transactions TO service_role;
GRANT SELECT ON TABLE public.wallet_transactions TO authenticated;


--
-- Name: TABLE wallets; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.wallets TO service_role;
GRANT SELECT ON TABLE public.wallets TO authenticated;


--
-- Name: TABLE withdrawals; Type: ACL; Schema: public; Owner: -
--

GRANT ALL ON TABLE public.withdrawals TO service_role;
GRANT SELECT ON TABLE public.withdrawals TO authenticated;


--
-- Name: DEFAULT PRIVILEGES FOR FUNCTIONS; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON FUNCTIONS TO service_role;


--
-- Name: DEFAULT PRIVILEGES FOR TABLES; Type: DEFAULT ACL; Schema: public; Owner: -
--

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO anon;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO authenticated;
ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public GRANT ALL ON TABLES TO service_role;


--
-- PostgreSQL database dump complete
--


