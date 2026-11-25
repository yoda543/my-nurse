-- 0010 · Données de santé : dossier médical, documents médicaux, constantes,
-- comptes rendus de soin reliés au patient, et lecture tracée du dossier.
--
-- Additive. Les colonnes médicales de patients (allergies, history,
-- treatments) sont COPIÉES dans medical_records et restent synchronisées
-- tant que l'app actuelle les utilise. Leur retrait est préparé dans
-- supabase/pending/ et ne s'exécute pas avec cette migration.

-- ============================================================ dossier médical
create table public.medical_records (
  patient_id uuid primary key references public.patients on delete cascade,
  blood_group text check (blood_group in ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-')),
  allergies text not null default '',
  chronic_conditions text not null default '',
  current_treatments text not null default '',
  history text not null default '',
  emergency_contact_name text,
  emergency_contact_phone text check (emergency_contact_phone ~ '^\+?[0-9 ]{8,16}$'),
  primary_doctor text,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles on delete set null
);
create index medical_records_updated_by_idx on public.medical_records (updated_by);

-- Reprise des données existantes.
insert into public.medical_records (patient_id, allergies, current_treatments, history)
select id, allergies, treatments, history from public.patients
on conflict (patient_id) do nothing;

-- Transition : l'app actuelle écrit encore dans patients ; on recopie.
create function private.sync_medical_record_from_patient() returns trigger
language plpgsql security definer set search_path = '' as $$
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
create trigger patients_sync_medical_record
  after insert or update of allergies, treatments, history on public.patients
  for each row execute function private.sync_medical_record_from_patient();

create function private.touch_medical_record() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  new.updated_at := now();
  new.updated_by := coalesce((select auth.uid()), new.updated_by);
  return new;
end;
$$;
create trigger medical_records_touch before update on public.medical_records
  for each row execute function private.touch_medical_record();

-- Commune où vit le patient : propose les bons soignants même quand un
-- proche réserve depuis l'étranger.
alter table public.patients add column if not exists commune text not null default ''
  check (length(commune) <= 40);
grant insert (commune), update (commune) on public.patients to authenticated;

-- ======================================================= documents médicaux
create type public.medical_doc_kind as enum
  ('prescription', 'lab_result', 'imaging', 'report', 'certificate', 'other');

create table public.medical_documents (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients on delete cascade,
  kind public.medical_doc_kind not null,
  title text not null check (length(trim(title)) between 1 and 120),
  storage_path text not null unique,
  mime_type text not null check (mime_type in ('application/pdf', 'image/jpeg', 'image/png')),
  size_bytes int not null check (size_bytes between 1 and 10485760),
  document_date date,
  booking_id uuid references public.bookings on delete set null,
  uploaded_by uuid not null references public.profiles on delete restrict,
  deleted_at timestamptz,
  deleted_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  -- Le fichier est rangé dans le dossier du patient : <patient_id>/<fichier>.
  check (storage_path like patient_id::text || '/%')
);
create index medical_documents_patient_idx on public.medical_documents (patient_id, created_at desc)
  where deleted_at is null;
create index medical_documents_booking_idx on public.medical_documents (booking_id);
create index medical_documents_uploaded_by_idx on public.medical_documents (uploaded_by);

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('medical-documents', 'medical-documents', false, 10485760,
        array['application/pdf', 'image/jpeg', 'image/png'])
on conflict (id) do nothing;

create function private.try_uuid(p text) returns uuid
language plpgsql immutable set search_path = '' as $$
begin
  return p::uuid;
exception when others then
  return null;
end;
$$;

-- ================================================================ constantes
create type public.vital_kind as enum (
  'blood_pressure', 'heart_rate', 'temperature', 'glycemia', 'spo2',
  'respiratory_rate', 'weight', 'pain_score'
);

create table public.vital_signs (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients on delete cascade,
  kind public.vital_kind not null,
  value numeric(6, 2) not null,
  value2 numeric(6, 2),           -- tension diastolique
  unit text not null,
  measured_at timestamptz not null default now(),
  booking_id uuid references public.bookings on delete set null,
  recorded_by uuid not null references public.profiles on delete restrict,
  note text not null default '' check (length(note) <= 500),
  entered_in_error boolean not null default false,
  created_at timestamptz not null default now(),
  check ((kind = 'blood_pressure') = (value2 is not null))
);
create index vital_signs_patient_idx on public.vital_signs (patient_id, kind, measured_at desc);
create index vital_signs_booking_idx on public.vital_signs (booking_id);
create index vital_signs_recorded_by_idx on public.vital_signs (recorded_by);

-- Unité imposée et valeurs plausibles (évite les erreurs de saisie).
create function private.check_vital_sign() returns trigger
language plpgsql set search_path = '' as $$
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
create trigger vital_signs_check before insert or update on public.vital_signs
  for each row execute function private.check_vital_sign();

-- ===================================================== comptes rendus de soin
-- Le patient est recopié depuis la réservation (index, règles d'accès).
alter table public.care_logs add column patient_id uuid references public.patients on delete cascade;
update public.care_logs c set patient_id = b.patient_id from public.bookings b
  where b.id = c.booking_id and c.patient_id is null;
create index care_logs_patient_idx on public.care_logs (patient_id, created_at desc);

create function private.care_log_fill() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  select patient_id into new.patient_id from public.bookings where id = new.booking_id;
  return new;
end;
$$;
create trigger care_logs_fill before insert on public.care_logs
  for each row execute function private.care_log_fill();

-- Les constantes saisies en texte libre dans le compte rendu sont aussi
-- enregistrées en mesures structurées quand elles sont lisibles
-- (« 13/8 » ou « 130/80 », « 37,5 », « 82 », « 1,10 »). Sinon on ignore.
create function private.num(p text) returns numeric
language plpgsql immutable set search_path = '' as $$
begin
  return nullif(replace(substring(p from '[0-9]+(?:[.,][0-9]+)?'), ',', '.'), '')::numeric;
exception when others then
  return null;
end;
$$;

create function private.care_log_vitals() returns trigger
language plpgsql security definer set search_path = '' as $$
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
create trigger care_logs_vitals after insert on public.care_logs
  for each row execute function private.care_log_vitals();

-- ================================================ lecture tracée du dossier
-- Seul chemin de lecture du dossier pour un soignant ou l'équipe MyNurse :
-- vérifie le périmètre autorisé, renvoie uniquement ce périmètre, et écrit
-- une ligne dans le journal d'audit à chaque appel.
create function public.get_patient_chart(p_patient uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
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

-- ================================================ règles d'accès (RLS)
alter table public.medical_records enable row level security;
alter table public.medical_documents enable row level security;
alter table public.vital_signs enable row level security;

revoke all on public.medical_records, public.medical_documents, public.vital_signs from anon, authenticated;

-- Dossier : lecture directe par le titulaire et les proches autorisés.
-- Les soignants passent par get_patient_chart (lecture tracée).
grant select on public.medical_records to authenticated;
grant insert (patient_id, blood_group, allergies, chronic_conditions, current_treatments, history,
              emergency_contact_name, emergency_contact_phone, primary_doctor)
  on public.medical_records to authenticated;
grant update (blood_group, allergies, chronic_conditions, current_treatments, history,
              emergency_contact_name, emergency_contact_phone, primary_doctor)
  on public.medical_records to authenticated;

create policy medical_records_select on public.medical_records for select to authenticated
  using ((select private.can_act_for(patient_id, 'view_records'))
      or (select private.member_has(patient_id, 'manage_records')));
create policy medical_records_insert on public.medical_records for insert to authenticated
  with check ((select private.can_act_for(patient_id, 'manage_records')));
create policy medical_records_update on public.medical_records for update to authenticated
  using ((select private.can_act_for(patient_id, 'manage_records')))
  with check ((select private.can_act_for(patient_id, 'manage_records')));

-- Documents : le titulaire, un proche autorisé ou un soignant ayant un accès
-- « documents » en cours peut en ajouter. Suppression = masquage (deleted_at).
grant select on public.medical_documents to authenticated;
grant insert (id, patient_id, kind, title, storage_path, mime_type, size_bytes, document_date, booking_id, uploaded_by)
  on public.medical_documents to authenticated;
grant update (deleted_at, deleted_by) on public.medical_documents to authenticated;

create policy medical_documents_select on public.medical_documents for select to authenticated
  using ((select private.can_act_for(patient_id, 'view_records'))
      or (select private.member_has(patient_id, 'manage_records'))
      or uploaded_by = (select auth.uid()));
create policy medical_documents_insert on public.medical_documents for insert to authenticated
  with check (uploaded_by = (select auth.uid())
    and ((select private.can_act_for(patient_id, 'manage_records'))
         or (select private.has_record_access(patient_id, 'documents'))));
create policy medical_documents_hide on public.medical_documents for update to authenticated
  using ((select private.can_act_for(patient_id, 'manage_records')) or uploaded_by = (select auth.uid()))
  with check (deleted_by = (select auth.uid()));

-- Constantes : saisies par le soignant pendant un accès en cours, ou par la
-- famille (mesure à domicile). Jamais modifiées : seulement marquées erronées
-- par leur auteur.
grant select on public.vital_signs to authenticated;
grant insert (patient_id, kind, value, value2, unit, measured_at, booking_id, recorded_by, note)
  on public.vital_signs to authenticated;
grant update (entered_in_error) on public.vital_signs to authenticated;

create policy vital_signs_select on public.vital_signs for select to authenticated
  using ((select private.can_act_for(patient_id, 'view_records'))
      or recorded_by = (select auth.uid()));
create policy vital_signs_insert on public.vital_signs for insert to authenticated
  with check (recorded_by = (select auth.uid())
    and ((select private.can_act_for(patient_id, 'manage_records'))
         or (select private.has_record_access(patient_id, 'vitals'))));
create policy vital_signs_flag on public.vital_signs for update to authenticated
  using (recorded_by = (select auth.uid())) with check (recorded_by = (select auth.uid()));

-- Fichiers : <patient_id>/<nom>. Lecture si accès « documents » ; dépôt si
-- droit d'ajout ; jamais de suppression du fichier depuis l'app.
create policy medical_files_read on storage.objects for select to authenticated
  using (bucket_id = 'medical-documents'
    and (select private.has_record_access(private.try_uuid((storage.foldername(name))[1]), 'documents')));
create policy medical_files_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'medical-documents'
    and ((select private.can_act_for(private.try_uuid((storage.foldername(name))[1]), 'manage_records'))
         or (select private.has_record_access(private.try_uuid((storage.foldername(name))[1]), 'documents'))));

-- ============================================================ audit : tables
create trigger medical_records_audit after insert or update or delete on public.medical_records
  for each row execute function audit.log_change('phi', 'patient_id', 'patient_id');
create trigger medical_documents_audit after insert or update or delete on public.medical_documents
  for each row execute function audit.log_change('phi', 'patient_id');
create trigger vital_signs_audit after insert or update or delete on public.vital_signs
  for each row execute function audit.log_change('phi', 'patient_id');

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
revoke execute on function public.get_patient_chart(uuid) from public, anon;
grant execute on function public.get_patient_chart(uuid) to authenticated;
