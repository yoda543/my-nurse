-- Retour arrière de 0010_clinical.sql. À exécuter dans une transaction,
-- après 0011_down.sql et avant 0009_down.sql.
-- Les allergies, traitements et antécédents du dossier sont d'abord recopiés
-- dans patients (dernière valeur conservée).
-- Données perdues : medical_records (groupe sanguin, maladies chroniques,
-- contact d'urgence, médecin traitant), medical_documents (les fichiers du
-- bucket medical-documents sont conservés), vital_signs,
-- care_logs.patient_id (recalculable depuis bookings).

-- Garde-fou : ne s'exécute que si on le confirme explicitement dans la session :
--   set mynurse.confirm_rollback = 'yes';
-- AVANT : exporter les tables listées ci-dessous (pg_dump --data-only -t …).
do $$
begin
  if current_setting('mynurse.confirm_rollback', true) is distinct from 'yes' then
    raise exception 'Retour arrière non confirmé (set mynurse.confirm_rollback = yes).';
  end if;
end $$;

drop trigger if exists patients_sync_medical_record on public.patients;
do $$
begin
  if to_regclass('public.medical_records') is not null then
    update public.patients p
      set allergies = r.allergies, treatments = r.current_treatments, history = r.history
      from public.medical_records r
      where r.patient_id = p.id
        and (p.allergies, p.treatments, p.history) is distinct from (r.allergies, r.current_treatments, r.history);
  end if;
end $$;

drop policy if exists medical_files_read on storage.objects;
drop policy if exists medical_files_upload on storage.objects;
-- Le bucket n'est retiré que s'il est vide (aucun fichier supprimé ici).
delete from storage.buckets b where b.id = 'medical-documents'
  and not exists (select 1 from storage.objects o where o.bucket_id = b.id);

drop trigger if exists care_logs_fill on public.care_logs;
drop trigger if exists care_logs_vitals on public.care_logs;
drop function if exists public.get_patient_chart(uuid);
drop table if exists public.vital_signs, public.medical_documents, public.medical_records;
drop function if exists private.sync_medical_record_from_patient(), private.touch_medical_record(),
  private.check_vital_sign(), private.care_log_fill(), private.care_log_vitals(),
  private.num(text), private.try_uuid(text);
drop type if exists public.vital_kind, public.medical_doc_kind;
alter table public.care_logs drop column if exists patient_id;
alter table public.patients drop column if exists commune;
