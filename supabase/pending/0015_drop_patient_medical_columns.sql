-- Étape C — DESTRUCTIF. Prérequis :
--   1. 0014 appliquée depuis au moins 30 jours, aucune erreur remontée ;
--   2. sauvegarde : pg_dump --data-only -t public.patients > patients_avant_0013.sql
--   3. contrôle : la requête ci-dessous renvoie 0.
--      select count(*) from public.patients p join public.medical_records r on r.patient_id = p.id
--      where (p.allergies, p.treatments, p.history) is distinct from (r.allergies, r.current_treatments, r.history)
--        and r.updated_at < (select max(occurred_at) from audit.events where entity = 'patients');
do $$
begin
  if current_setting('mynurse.confirm_drop', true) is distinct from 'yes' then
    raise exception 'Suppression non confirmée (set mynurse.confirm_drop = yes).';
  end if;
end $$;

drop function if exists private.sync_medical_record_from_patient();
alter table public.patients
  drop column allergies,
  drop column history,
  drop column treatments;
