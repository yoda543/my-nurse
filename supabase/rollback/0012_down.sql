-- Retour arrière de 0012_pro_workspace.sql (avant 0011_down.sql).
-- Données perdues : journal de visite, incidents, motifs de refus, dates
-- de validité des pièces.
-- Non réversible sans risque : les valeurs ajoutées à l'enum
-- verification_status (incomplete, under_review, expired) restent définies
-- (PostgreSQL ne sait pas les retirer) ; les dossiers dans ces états sont
-- remis « en attente » ci-dessous.

-- Garde-fou : ne s'exécute que si on le confirme explicitement dans la session :
--   set mynurse.confirm_rollback = 'yes';
do $$
begin
  if current_setting('mynurse.confirm_rollback', true) is distinct from 'yes' then
    raise exception 'Retour arrière non confirmé (set mynurse.confirm_rollback = yes).';
  end if;
end $$;

update public.pros set verification_status = 'pending'
  where verification_status::text in ('incomplete', 'under_review', 'expired');
select cron.unschedule('expire-pro-documents');

-- Fonctions remises dans leur version précédente (0004, 0009, 0010, 0011).
CREATE OR REPLACE FUNCTION public.search_pros(p_service text, p_commune text)
 RETURNS TABLE(id uuid, display_name text, pro_type pro_type, price integer, rating_avg numeric, rating_count integer, care_count integer, featured boolean)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select p.id, p.display_name, p.pro_type, ps.price, p.rating_avg, p.rating_count, p.care_count,
         coalesce(p.premium_until > now(), false) as featured
  from public.pros p
  join public.pro_services ps on ps.pro_id = p.id and ps.service_id = p_service
  where p.verification_status = 'verified' and p_commune = any (p.communes)
  order by featured desc, p.rating_avg desc;
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
$function$
;

CREATE OR REPLACE FUNCTION public.admin_reject_pro(p_pro uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

CREATE OR REPLACE FUNCTION public.get_patient_chart(p_patient uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
$function$
;

drop trigger if exists bookings_price_zz0_active on public.bookings;
drop trigger if exists bookings_accept_active on public.bookings;
drop trigger if exists vital_signs_scope on public.vital_signs;
drop function if exists public.submit_pro_dossier(), public.admin_start_review(uuid),
  public.expire_pro_documents(), public.refuse_booking(uuid, text),
  public.add_care_journal(uuid, text, text),
  public.report_incident(uuid, public.incident_category, text);
drop table if exists public.incident_reports, public.care_journal_entries;
drop type if exists public.incident_category;
drop function if exists private.check_pro_active(), private.check_pro_active_on_accept(),
  private.check_vital_scope(), private.vital_in_scope(public.pro_type, public.vital_kind),
  private.pro_is_active(uuid), private.pro_docs_ok(uuid);
alter table public.bookings drop column if exists refusal_reason;
drop index if exists public.pro_documents_expiry_idx;
alter table public.pro_documents drop column if exists expires_on;
