-- Étape B. Prérequis : l'app lit et écrit le dossier dans medical_records
-- (titulaire, proches) et via get_patient_chart (soignants).
-- Non destructif : les colonnes restent en base, seulement plus exposées.
-- Retour arrière : grant select, insert, update on public.patients to authenticated;
--                  et recréer le déclencheur patients_sync_medical_record (0010).

-- medical_records fait foi : la recopie depuis patients s'arrête ici.
drop trigger if exists patients_sync_medical_record on public.patients;

-- Les soignants (règle patients_pro) ne lisent plus que l'identité.
revoke select, insert, update on public.patients from authenticated;
grant select (id, owner_id, full_name, birth_date, relation, created_at) on public.patients to authenticated;
grant insert (id, owner_id, full_name, birth_date, relation) on public.patients to authenticated;
grant update (full_name, birth_date, relation) on public.patients to authenticated;
