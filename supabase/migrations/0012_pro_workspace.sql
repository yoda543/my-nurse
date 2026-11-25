-- 0012 · Espace soignant : statuts de vérification complets, validité des
-- pièces, champ d'exercice appliqué par la base, refus motivé, journal de
-- visite, incidents.
--
-- Additive. Les nouvelles valeurs d'enum ne sont utilisées que dans des
-- corps de fonctions (pas d'emploi direct dans la même transaction).

-- ===================================================== statuts du dossier
alter type public.verification_status add value if not exists 'incomplete';
alter type public.verification_status add value if not exists 'under_review';
alter type public.verification_status add value if not exists 'expired';

-- Fin de validité d'une pièce (CNI, assurance, inscription à l'Ordre…).
alter table public.pro_documents add column if not exists expires_on date;
create index if not exists pro_documents_expiry_idx on public.pro_documents (expires_on)
  where expires_on is not null;
grant insert (expires_on) on public.pro_documents to authenticated;

-- Motif d'un refus, visible par le patient.
alter table public.bookings add column if not exists refusal_reason text not null default ''
  check (length(refusal_reason) <= 200);

-- Toutes les pièces exigées sont présentes et en cours de validité.
create function private.pro_docs_ok(p_pro uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select not exists (
    select unnest(private.required_docs(p.pro_type))
    from public.pros p where p.id = p_pro
    except
    select d.doc_type from public.pro_documents d
    where d.pro_id = p_pro and (d.expires_on is null or d.expires_on > current_date)
  );
$$;

-- Un soignant reçoit des demandes seulement s'il est vérifié ET à jour.
create function private.pro_is_active(p_pro uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.pros where id = p_pro and verification_status::text = 'verified'
  ) and private.pro_docs_ok(p_pro);
$$;

-- Garde-fou à la réservation (après bookings_price, ordre alphabétique) :
-- un dossier vérifié dont une pièce a expiré ne reçoit plus de demande.
create function private.check_pro_active() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not private.pro_is_active(new.pro_id) then
    raise exception 'Ce soignant n''est pas disponible pour le moment.';
  end if;
  return new;
end;
$$;
create trigger bookings_price_zz0_active before insert on public.bookings
  for each row execute function private.check_pro_active();

-- Et à l'acceptation : un soignant non actif ne peut pas accepter.
create function private.check_pro_active_on_accept() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if new.status = 'accepted' and old.status = 'pending' and not private.pro_is_active(new.pro_id) then
    raise exception 'Votre compte n''est pas vérifié ou une pièce a expiré : vous ne pouvez pas accepter de soin.';
  end if;
  return new;
end;
$$;
create trigger bookings_accept_active before update of status on public.bookings
  for each row execute function private.check_pro_active_on_accept();

-- La recherche n'affiche que les soignants actifs.
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
  order by featured desc, p.rating_avg desc;
$$;

-- Dossier envoyé ou complété par le soignant : le statut suit les pièces.
--   incomplet / refusé + complet  → en attente
--   expiré (pièce renouvelée)     → en examen
--   pièces manquantes             → incomplet
create function public.submit_pro_dossier() returns text
language plpgsql security definer set search_path = '' as $$
declare
  v_status text;
  v_ok boolean;
begin
  select verification_status::text into v_status from public.pros where id = (select auth.uid());
  if v_status is null then
    raise exception 'Compte soignant introuvable.';
  end if;
  v_ok := private.pro_docs_ok((select auth.uid()));
  if v_status = 'suspended' then
    raise exception 'Compte suspendu : contactez le support MyNurse.';
  elsif not v_ok and v_status in ('pending', 'incomplete', 'rejected') then
    v_status := 'incomplete';
  elsif v_ok and v_status in ('incomplete', 'rejected') then
    v_status := 'pending';
    perform private.notify_admins('Dossier complet à vérifier', 'Un soignant a complété son dossier.');
  elsif v_ok and v_status = 'expired' then
    v_status := 'under_review';
    perform private.notify_admins('Pièce renouvelée à contrôler', 'Un soignant a déposé une pièce à jour.');
  end if;
  update public.pros
    set verification_status = v_status::public.verification_status,
        rejection_reason = case when v_status = 'pending' then '' else rejection_reason end
    where id = (select auth.uid());
  return v_status;
end;
$$;

create function public.admin_start_review(p_pro uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_perm('verify_pros');
  update public.pros set verification_status = 'under_review'::text::public.verification_status
    where id = p_pro and verification_status::text = 'pending';
  if not found then
    raise exception 'Ce dossier n''est pas en attente.';
  end if;
  perform private.notify(p_pro, 'Dossier en cours d''examen',
    'Un vérificateur MyNurse contrôle vos pièces. Il peut vous appeler.');
end;
$$;

-- Validation : depuis en attente, en examen, suspendu ou expiré ; toutes
-- les pièces doivent être à jour. Sinon identique à 0011.
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
    from public.pros
    where id = p_pro and verification_status::text in ('pending', 'under_review', 'suspended', 'expired');
  if v_type is null then
    raise exception 'Ce dossier n''est pas à valider.';
  end if;
  if not private.pro_docs_ok(p_pro) then
    raise exception 'Dossier incomplet ou pièce expirée.';
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

create or replace function public.admin_reject_pro(p_pro uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
begin
  perform private.require_perm('verify_pros');
  if coalesce(trim(p_reason), '') = '' then
    raise exception 'Indiquez un motif.';
  end if;
  update public.pros set verification_status = 'rejected', rejection_reason = p_reason
    where id = p_pro and verification_status::text in ('pending', 'under_review', 'incomplete');
  if not found then
    raise exception 'Ce dossier n''est pas en attente.';
  end if;
end;
$$;

-- Chaque jour : un dossier vérifié dont une pièce a expiré passe en
-- « expiré » (il ne reçoit déjà plus de demande) et le soignant est prévenu.
create function public.expire_pro_documents() returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_count int := 0;
begin
  for v_id in
    select id from public.pros
    where verification_status::text = 'verified' and not private.pro_docs_ok(id)
  loop
    update public.pros set verification_status = 'expired'::text::public.verification_status where id = v_id;
    perform private.notify(v_id, 'Pièce expirée',
      'Une pièce obligatoire a expiré : vous ne recevez plus de demandes. Déposez la nouvelle version.');
    v_count := v_count + 1;
  end loop;
  return v_count;
end;
$$;
select cron.schedule('expire-pro-documents', '17 5 * * *', 'select public.expire_pro_documents()');

-- ============================================ champ d'exercice (base)
-- Constantes qu'une profession peut relever (même règle que l'app).
create function private.vital_in_scope(p_type public.pro_type, p_kind public.vital_kind) returns boolean
language sql immutable set search_path = '' as $$
  select case p_type
    when 'aide_soignant' then p_kind in ('temperature', 'heart_rate', 'weight', 'pain_score')
    when 'kine' then p_kind in ('blood_pressure', 'heart_rate', 'spo2', 'respiratory_rate', 'pain_score')
    else true
  end;
$$;

create function private.check_vital_scope() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_type public.pro_type;
begin
  select pro_type into v_type from public.pros where id = new.recorded_by;
  if v_type is not null and not private.vital_in_scope(v_type, new.kind) then
    raise exception 'Mesure hors du champ d''exercice de votre profession.';
  end if;
  return new;
end;
$$;
create trigger vital_signs_scope before insert on public.vital_signs
  for each row execute function private.check_vital_scope();

-- Lecture du dossier par un soignant : son autorisation en cours ET sa
-- profession. Un(e) aide-soignant(e) voit l'essentiel (identité,
-- allergies, traitements), pas les documents, constantes ni antécédents.
-- Sinon identique à 0010.
create or replace function public.get_patient_chart(p_patient uuid) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_summary boolean := private.has_record_access(p_patient, 'summary');
  v_vitals boolean := private.has_record_access(p_patient, 'vitals');
  v_docs boolean := private.has_record_access(p_patient, 'documents');
  v_reports boolean := private.has_record_access(p_patient, 'reports');
  v_limited boolean := exists (
    select 1 from public.pros where id = (select auth.uid()) and pro_type = 'aide_soignant');
  v_result jsonb;
begin
  if not (v_summary or v_vitals or v_docs or v_reports) then
    raise exception 'Vous n''avez pas accès à ce dossier.';
  end if;
  if v_limited then
    v_vitals := false;
    v_docs := false;
    v_reports := false;
  end if;

  select jsonb_build_object(
    'patient', case when v_summary then jsonb_build_object(
        'id', p.id, 'full_name', p.full_name, 'birth_date', p.birth_date) end,
    'record', case when v_summary then
        case when v_limited
          then jsonb_build_object('allergies', r.allergies, 'current_treatments', r.current_treatments,
                                  'emergency_contact_name', r.emergency_contact_name)
          else to_jsonb(r) - 'updated_by' end end,
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
      jsonb_build_object('summary', v_summary, 'vitals', v_vitals, 'documents', v_docs,
                         'reports', v_reports, 'limited', v_limited));
  end if;
  return v_result;
end;
$$;

-- ======================================================== refus motivé
create function public.refuse_booking(p_booking uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
declare
  v_contract uuid;
begin
  select contract_id into v_contract from public.bookings
    where id = p_booking and pro_id = (select auth.uid()) and status = 'pending';
  if not found then
    raise exception 'Demande introuvable ou déjà traitée.';
  end if;
  perform public.respond_booking(p_booking, false);
  update public.bookings set refusal_reason = left(trim(coalesce(p_reason, '')), 200)
    where (id = p_booking or (v_contract is not null and contract_id = v_contract))
      and status = 'refused';
end;
$$;

-- ==================================================== journal de visite
create table public.care_journal_entries (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings on delete cascade,
  pro_id uuid not null references public.pros on delete cascade,
  kind text not null check (kind in ('on_the_way', 'arrived', 'note', 'left')),
  text text not null default '' check (length(text) <= 1000),
  created_at timestamptz not null default now()
);
create index care_journal_booking_idx on public.care_journal_entries (booking_id, created_at);
create index care_journal_pro_idx on public.care_journal_entries (pro_id);
create unique index care_journal_once_idx on public.care_journal_entries (booking_id, kind)
  where kind in ('on_the_way', 'arrived', 'left');

-- Le soignant note une étape ; « en route » et « arrivé » préviennent la
-- famille (private.notify copie au titulaire et aux proches autorisés).
create function public.add_care_journal(p_booking uuid, p_kind text, p_text text default '')
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  b public.bookings;
  v_id uuid;
  v_pro text;
begin
  select * into b from public.bookings
    where id = p_booking and pro_id = (select auth.uid()) and status = 'accepted' and paid_at is not null;
  if b.id is null then
    raise exception 'Ce soin n''est pas confirmé et payé, ou ne vous est pas attribué.';
  end if;
  if not private.pro_is_active(b.pro_id) then
    raise exception 'Votre compte n''est pas actif.';
  end if;
  if p_kind = 'on_the_way' and b.scheduled_at - now() > interval '3 hours' then
    raise exception 'Trop tôt : indiquez « Je pars » au plus 3 h avant le soin.';
  end if;
  if p_kind = 'arrived' and now() < b.scheduled_at - interval '30 minutes' then
    raise exception 'L''arrivée se note à partir de 30 minutes avant le soin.';
  end if;
  insert into public.care_journal_entries (booking_id, pro_id, kind, text)
    values (p_booking, b.pro_id, p_kind, coalesce(p_text, ''))
    on conflict do nothing
    returning id into v_id;
  select display_name into v_pro from public.pros where id = b.pro_id;
  if v_id is not null and p_kind = 'on_the_way' then
    perform private.notify(b.booked_by, v_pro || ' est en route',
      'Prévenez la personne sur place.', p_booking);
  elsif v_id is not null and p_kind = 'arrived' then
    perform private.notify(b.booked_by, v_pro || ' est arrivé(e)', 'Le soin commence.', p_booking);
  end if;
  return v_id;
end;
$$;

-- ============================================================ incidents
create type public.incident_category as enum
  ('patient_danger', 'insecurity', 'adverse_event', 'equipment', 'address_not_found', 'other');

create table public.incident_reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid not null references public.profiles on delete cascade,
  booking_id uuid references public.bookings on delete set null,
  category public.incident_category not null,
  description text not null check (length(trim(description)) between 10 and 4000),
  urgent boolean not null default false,
  status text not null default 'open' check (status in ('open', 'in_review', 'closed')),
  resolution text,
  handled_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index incident_reports_reporter_idx on public.incident_reports (reporter_id, created_at desc);
create index incident_reports_queue_idx on public.incident_reports (urgent desc, created_at)
  where status <> 'closed';
create index incident_reports_booking_idx on public.incident_reports (booking_id);
create index incident_reports_handled_idx on public.incident_reports (handled_by);

create function public.report_incident(p_booking uuid, p_category public.incident_category, p_description text)
returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_urgent boolean := p_category in ('patient_danger', 'insecurity', 'adverse_event');
begin
  if not exists (select 1 from public.pros where id = (select auth.uid())) then
    raise exception 'Réservé aux soignants.';
  end if;
  if p_booking is not null and not exists (
    select 1 from public.bookings where id = p_booking and pro_id = (select auth.uid())
  ) then
    raise exception 'Ce soin ne vous est pas attribué.';
  end if;
  insert into public.incident_reports (reporter_id, booking_id, category, description, urgent)
    values ((select auth.uid()), p_booking, p_category, p_description, v_urgent)
    returning id into v_id;
  perform private.notify_admins(
    case when v_urgent then 'Urgent : incident signalé' else 'Incident signalé' end,
    'Un soignant a signalé un incident.');
  return v_id;
end;
$$;

-- ================================================ règles d'accès (RLS)
alter table public.care_journal_entries enable row level security;
alter table public.incident_reports enable row level security;
revoke all on public.care_journal_entries, public.incident_reports from anon, authenticated;
grant select on public.care_journal_entries, public.incident_reports to authenticated;

-- Journal : le soignant, celui qui a réservé, et les proches qui suivent.
create policy care_journal_select on public.care_journal_entries for select to authenticated
  using (pro_id = (select auth.uid()) or exists (
    select 1 from public.bookings b
    where b.id = booking_id
      and (b.booked_by = (select auth.uid())
           or (select private.can_act_for(b.patient_id, 'view_reports'))
           or (select private.member_has(b.patient_id, 'book_care')))
  ));

create policy incident_reports_select on public.incident_reports for select to authenticated
  using (reporter_id = (select auth.uid()) or (select private.has_perm('support')));

-- ============================================================ audit
create trigger incident_reports_audit after insert or update on public.incident_reports
  for each row execute function audit.log_change('full');
create trigger care_journal_audit after insert on public.care_journal_entries
  for each row execute function audit.log_change('full');

-- ========================================================= droits
revoke execute on all functions in schema private from public, anon, authenticated;
grant execute on function
  private.is_admin(), private.require_admin(), private.required_docs(public.pro_type),
  private.owns_patient(uuid), private.treats_patient(uuid),
  private.has_perm(public.staff_permission), private.has_any_perm(public.staff_permission[]),
  private.member_has(uuid, public.member_permission), private.is_member(uuid),
  private.can_act_for(uuid, public.member_permission),
  private.has_record_access(uuid, public.record_scope), private.try_uuid(text),
  private.pro_docs_ok(uuid)
to authenticated;
revoke execute on function
  public.submit_pro_dossier(), public.admin_start_review(uuid), public.refuse_booking(uuid, text),
  public.add_care_journal(uuid, text, text),
  public.report_incident(uuid, public.incident_category, text)
from public, anon;
grant execute on function
  public.submit_pro_dossier(), public.admin_start_review(uuid), public.refuse_booking(uuid, text),
  public.add_care_journal(uuid, text, text),
  public.report_incident(uuid, public.incident_category, text)
to authenticated;
revoke execute on function public.expire_pro_documents() from public, anon, authenticated;
