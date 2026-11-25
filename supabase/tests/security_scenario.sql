-- Scénario de sécurité des migrations 0009-0011, joué en local
-- (voir run_local.sh). Chaque contrôle affiche « OK … » ; le premier échec
-- arrête le script. Jamais exécuté sur la production.

\set ON_ERROR_STOP on
\o /dev/null
set client_min_messages = notice;

create function pg_temp.ok(p_cond boolean, p_label text) returns void
language plpgsql as $$
begin
  if p_cond is not true then
    raise exception 'ÉCHEC : %', p_label;
  end if;
  raise notice 'OK %', p_label;
end;
$$;

-- La requête doit être refusée (exception), avec le rôle courant.
create function pg_temp.refused(p_sql text, p_label text) returns void
language plpgsql as $$
begin
  begin
    execute p_sql;
  exception when others then
    raise notice 'OK % (refusé : %)', p_label, sqlerrm;
    return;
  end;
  raise exception 'ÉCHEC : % aurait dû être refusé', p_label;
end;
$$;
grant execute on all functions in schema pg_temp to authenticated;

-- ------------------------------------------------------------- comptes
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'patient@test.ci', '{"full_name":"Marie Kouadio"}'),
  ('00000000-0000-0000-0000-00000000000f', 'fille@test.ci',   '{"full_name":"Awa Kouadio"}'),
  ('00000000-0000-0000-0000-0000000000a1', 'aya@test.ci',     '{"role":"pro","full_name":"Aya Kouamé"}'),
  ('00000000-0000-0000-0000-0000000000b1', 'serge@test.ci',   '{"role":"pro","full_name":"Serge Aka"}'),
  ('00000000-0000-0000-0000-0000000000c1', 'autre@test.ci',   '{"full_name":"Inconnu"}'),
  ('00000000-0000-0000-0000-0000000000d1', 'admin@test.ci',   '{"full_name":"Admin Principal"}'),
  ('00000000-0000-0000-0000-0000000000d2', 'support@test.ci', '{"full_name":"Agent Support"}');
-- Amorçage (fait par le serveur) : l'admin principal a tout sauf l'urgence,
-- l'agent n'a que le support.
select public.bootstrap_staff('00000000-0000-0000-0000-0000000000d1',
  '{verify_pros,manage_bookings,finance,support,moderate,audit_read,manage_settings,manage_staff}');
select public.bootstrap_staff('00000000-0000-0000-0000-0000000000d2', '{support}');
select pg_temp.refused($$select public.bootstrap_staff('00000000-0000-0000-0000-0000000000d2', '{medical_break_glass}')$$,
  'amorçage : jamais d''accès d''urgence');

\set P   '00000000-0000-0000-0000-00000000000a'
\set F   '00000000-0000-0000-0000-00000000000f'
\set A   '00000000-0000-0000-0000-0000000000a1'
\set B   '00000000-0000-0000-0000-0000000000b1'
\set O   '00000000-0000-0000-0000-0000000000c1'
\set X   '00000000-0000-0000-0000-0000000000d1'
\set Y   '00000000-0000-0000-0000-0000000000d2'
\set PAT '10000000-0000-0000-0000-000000000001'

-- ---------------------------------------------- soignants : inscription
select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
insert into public.pros (id, display_name, pro_type, communes) values (:'A', 'Aya Kouamé', 'infirmier', '{Cocody}');
insert into public.pro_documents (pro_id, doc_type, storage_path)
select :'A', d, :'A' || '/' || d || '.pdf' from unnest(array['diplome','autorisation','ordre','cni','rc_pro']) d;
reset role;
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
insert into public.pros (id, display_name, pro_type, communes) values (:'B', 'Serge Aka', 'infirmier', '{Cocody}');
insert into public.pro_documents (pro_id, doc_type, storage_path)
select :'B', d, :'B' || '/' || d || '.pdf' from unnest(array['diplome','autorisation','ordre','cni','rc_pro']) d;
reset role;

-- L'agent support ne peut pas valider un dossier ; l'admin principal oui.
select set_config('request.jwt.claim.sub', :'Y', false); set role authenticated;
select pg_temp.refused($$select public.admin_verify_pro('00000000-0000-0000-0000-0000000000a1')$$,
  'support sans verify_pros ne valide pas un soignant');
select pg_temp.ok((select count(*) from public.pro_documents) = 0, 'support ne voit pas les pièces des soignants');
reset role;
select set_config('request.jwt.claim.sub', :'X', false); set role authenticated;
select public.admin_verify_pro(:'A');
select public.admin_verify_pro(:'B');
select pg_temp.ok((select count(*) from public.pro_documents) = 10, 'verify_pros voit les pièces');
reset role;

-- Tarifs : contrôle de la fourchette du catalogue (pansement : 5 000 - 15 000).
select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
select pg_temp.refused($$insert into public.pro_services (pro_id, service_id, price)
  values ('00000000-0000-0000-0000-0000000000a1', 'pansement', 50000)$$, 'prix hors fourchette');
insert into public.pro_services (pro_id, service_id, price) values (:'A', 'pansement', 8000);
reset role;
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
insert into public.pro_services (pro_id, service_id, price) values (:'B', 'pansement', 9000);
reset role;

-- ------------------------------------------------- patient et dossier
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
insert into public.patients (id, owner_id, full_name, relation, allergies, treatments, history)
values (:'PAT', :'P', 'Marie Kouadio', 'moi', 'Pénicilline', 'Metformine 500 mg', 'Diabète type 2');
select pg_temp.ok((select allergies from public.medical_records where patient_id = :'PAT') = 'Pénicilline',
  'dossier médical recopié depuis la fiche patient');
update public.medical_records set blood_group = 'O+' where patient_id = :'PAT';
select public.add_patient_member(:'PAT', 'fille@test.ci', 'family', '{view_records,book_care}', null, 'Awa Kouadio', 'Fille');
select pg_temp.refused($$select public.add_patient_member('10000000-0000-0000-0000-000000000001',
  'personne@nulle.part', 'family', '{view_records}')$$, 'invitation d''un compte inexistant (message neutre)');
reset role;

-- Les autres ne voient ni la fiche ni le dossier.
select pg_temp.ok((select display_name || '|' || relation_label || '|' || contact_hint from public.patient_members)
  = 'Awa Kouadio|Fille|…t.ci', 'titulaire : nom, lien et contact masqué du proche');
select set_config('request.jwt.claim.sub', :'O', false); set role authenticated;
select pg_temp.ok((select count(*) from public.patients) = 0, 'inconnu : aucune fiche patient');
select pg_temp.ok((select count(*) from public.medical_records) = 0, 'inconnu : aucun dossier');
select pg_temp.refused($$select public.get_patient_chart('10000000-0000-0000-0000-000000000001')$$,
  'inconnu : lecture du dossier');
select pg_temp.refused($$select public.add_patient_member('10000000-0000-0000-0000-000000000001',
  'autre@test.ci', 'family', '{view_records}')$$, 'inconnu ne s''ajoute pas comme proche');
reset role;

-- La fille (proche autorisée) lit le dossier directement.
select set_config('request.jwt.claim.sub', :'F', false); set role authenticated;
select pg_temp.ok((select count(*) from public.patients) = 1, 'proche : voit la fiche');
select pg_temp.ok((select blood_group from public.medical_records) = 'O+', 'proche view_records : lit le dossier');
select pg_temp.ok((select owner_name from public.my_shared_patients()) = 'Marie Kouadio',
  'proche : dossier confié, avec le nom du titulaire');
select pg_temp.ok((select count(*) from public.patient_members) = 1, 'proche : voit sa propre autorisation');
-- Sans manage_records, la règle d'accès filtre la ligne : 0 ligne modifiée.
update public.medical_records set allergies = '' where patient_id = :'PAT';
reset role;
select pg_temp.ok((select allergies from public.medical_records where patient_id = :'PAT') = 'Pénicilline',
  'proche sans manage_records : la modification n''a rien changé');

-- ---------------------------------------------------- réservation
select confirm_topup from public.confirm_topup(:'P', 50000, 'wave', 'WAVE-1');
select set_config('request.jwt.claim.sub', :'F', false); set role authenticated;
-- La proche (book_care) peut réserver pour sa mère.
insert into public.bookings (id, booked_by, patient_id, pro_id, service_id, commune, address, scheduled_at)
values ('20000000-0000-0000-0000-0000000000f1', :'F', :'PAT', :'B', 'pansement', 'Cocody',
        'Cocody Angré 8e tranche', date_trunc('day', now() at time zone 'Africa/Abidjan' + interval '3 days') + interval '10 hours');
reset role;
select set_config('request.jwt.claim.sub', :'O', false); set role authenticated;
select pg_temp.refused($$insert into public.bookings (booked_by, patient_id, pro_id, service_id, commune, address, scheduled_at)
  values ('00000000-0000-0000-0000-0000000000c1', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1',
  'pansement', 'Cocody', 'Cocody Angré 8e tranche', now() + interval '2 days')$$, 'inconnu ne réserve pas pour ce patient');
reset role;

select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
insert into public.bookings (id, booked_by, patient_id, pro_id, service_id, commune, address, scheduled_at)
values ('20000000-0000-0000-0000-000000000001', :'P', :'PAT', :'A', 'pansement', 'Cocody',
        'Cocody Angré 8e tranche', date_trunc('day', now() at time zone 'Africa/Abidjan' + interval '1 day') + interval '10 hours');
select pg_temp.ok((select commission_rate from public.bookings where id = '20000000-0000-0000-0000-000000000001') = 0.10,
  'commission 10 % lue dans platform_settings');
reset role;

-- Demande en attente : Aya voit le résumé (allergies), pas les constantes.
select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
select pg_temp.ok((select public.get_patient_chart(:'PAT') -> 'record' ->> 'allergies') = 'Pénicilline',
  'soignant (demande) : résumé du dossier visible');
select pg_temp.ok((select public.get_patient_chart(:'PAT') -> 'vitals') = 'null'::jsonb,
  'soignant (demande) : constantes masquées');
select pg_temp.ok((select count(*) from public.medical_records) = 0,
  'soignant : pas de lecture directe du dossier (seulement la lecture tracée)');
select public.respond_booking('20000000-0000-0000-0000-000000000001', true);
select pg_temp.ok((select public.get_patient_chart(:'PAT') -> 'vitals') = '[]'::jsonb,
  'soignant (accepté) : constantes visibles');
reset role;
select pg_temp.ok(exists (select 1 from public.notifications
  where user_id = :'F' and booking_id = '20000000-0000-0000-0000-000000000001'),
  'famille : la proche est prévenue de la confirmation');
select pg_temp.ok(not exists (select 1 from public.notifications
  where user_id = :'O' and booking_id = '20000000-0000-0000-0000-000000000001'),
  'famille : personne d''autre n''est prévenu');
select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
reset role;

-- Serge (autre soignant, sa propre demande) ne voit que le résumé ;
-- un soignant sans demande ne voit rien.
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
select pg_temp.ok((select public.get_patient_chart(:'PAT') -> 'reports') = 'null'::jsonb,
  'autre soignant (demande en attente) : pas les comptes rendus');
select public.respond_booking('20000000-0000-0000-0000-0000000000f1', false);
select pg_temp.refused($$select public.get_patient_chart('10000000-0000-0000-0000-000000000001')$$,
  'soignant ayant refusé : accès retiré');
reset role;

-- Paiement, compte rendu, constantes structurées.
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select public.pay_booking_with_wallet('20000000-0000-0000-0000-000000000001');
reset role;
update public.bookings set scheduled_at = now() + interval '10 minutes',
  slot = tstzrange(now() + interval '10 minutes', now() + interval '55 minutes')
  where id = '20000000-0000-0000-0000-000000000001';
select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
insert into public.care_logs (booking_id, pro_id, arrived_at, left_at, blood_pressure, temperature, pulse, glycemia, acts)
values ('20000000-0000-0000-0000-000000000001', :'A', now(), now() + interval '40 minutes',
        '13/8', '37,4', '82 bpm', '1,26', 'Pansement de plaie, nettoyage');
select pg_temp.ok((select count(*) from public.vital_signs) = 4, 'soignant : voit les 4 constantes qu''il a saisies');
select pg_temp.ok((select value2 from public.vital_signs where kind = 'blood_pressure') = 80,
  'tension 13/8 convertie en 130/80 mmHg');
select pg_temp.refused($$update public.vital_signs set value = 39 where kind = 'temperature'$$,
  'une mesure ne se corrige pas');
reset role;

-- La famille voit le compte rendu ; l'administration non.
select set_config('request.jwt.claim.sub', :'F', false); set role authenticated;
select pg_temp.ok((select count(*) from public.care_logs) = 1, 'proche : voit le compte rendu (view_records)');
reset role;
select set_config('request.jwt.claim.sub', :'X', false); set role authenticated;
select pg_temp.ok((select count(*) from public.care_logs) = 0, 'admin : pas d''accès aux comptes rendus');
select pg_temp.ok((select count(*) from public.medical_records) = 0, 'admin : pas d''accès au dossier');
select pg_temp.ok((select count(*) from public.vital_signs) = 0, 'admin : pas d''accès aux constantes');
select pg_temp.ok((select count(*) from public.bookings) = 2, 'admin manage_bookings : voit les rendez-vous');
select pg_temp.ok((select count(*) from public.wallets) >= 3, 'admin finance : voit les portefeuilles');
reset role;
select set_config('request.jwt.claim.sub', :'Y', false); set role authenticated;
select pg_temp.ok((select count(*) from public.wallets where owner_id <> :'Y') = 0, 'support : ne voit que son propre portefeuille');
select pg_temp.refused($$select * from public.admin_audit_events()$$, 'support : pas d''accès au journal');
reset role;

-- --------------------------------------- contrôle par le patient
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select pg_temp.ok((select count(*) from public.my_record_access_log(:'PAT') where action = 'read') >= 1,
  'patient : voit qui a lu son dossier');
-- Le patient retire l'accès d'Aya avant son expiration.
select public.revoke_record_access(id, 'Soin terminé')
  from public.record_access_grants where grantee_id = :'A' and revoked_at is null;
reset role;
select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
select pg_temp.refused($$select public.get_patient_chart('10000000-0000-0000-0000-000000000001')$$,
  'soignant : accès révoqué par le patient');
select pg_temp.ok((select count(*) from public.care_logs) = 1, 'soignant : garde son propre compte rendu');
reset role;

-- Accès accordé par le patient, limité dans le temps.
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select public.grant_record_access(:'PAT', :'B', '{summary}', now() + interval '7 days', 'Médecin traitant');
select pg_temp.refused($$select public.grant_record_access('10000000-0000-0000-0000-000000000001',
  '00000000-0000-0000-0000-0000000000b1', '{full}', now() + interval '2 years')$$, 'accès de plus de 365 jours');
reset role;
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
select pg_temp.ok(public.get_patient_chart(:'PAT') ? 'record', 'soignant : accès accordé par le patient');
reset role;
update public.record_access_grants set starts_at = now() - interval '8 days', expires_at = now() - interval '1 day'
  where grantee_id = :'B' and source = 'patient';
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
select pg_temp.refused($$select public.get_patient_chart('10000000-0000-0000-0000-000000000001')$$,
  'soignant : accès expiré');
reset role;

-- ------------------------------------------------- accès d'urgence
select set_config('request.jwt.claim.sub', :'X', false); set role authenticated;
select pg_temp.refused($$select public.admin_break_glass('10000000-0000-0000-0000-000000000001', 'Urgence vitale signalée par la famille')$$,
  'admin sans medical_break_glass');
select pg_temp.refused($$select public.admin_set_staff_permission('00000000-0000-0000-0000-0000000000d1', 'medical_break_glass', true)$$,
  'on ne s''attribue pas soi-même l''accès d''urgence');
select public.admin_set_staff_permission(:'Y', 'medical_break_glass', true);
reset role;
select set_config('request.jwt.claim.sub', :'Y', false); set role authenticated;
select pg_temp.refused($$select public.admin_break_glass('10000000-0000-0000-0000-000000000001', 'court')$$,
  'accès d''urgence sans motif détaillé');
select public.admin_break_glass(:'PAT', 'Urgence vitale signalée par la famille');
select pg_temp.ok(public.get_patient_chart(:'PAT') ? 'vitals', 'accès d''urgence : dossier lisible');
reset role;
select pg_temp.ok(exists (select 1 from public.notifications
  where user_id = :'P' and title = 'Accès d''urgence à un dossier'), 'accès d''urgence notifié au patient');
select pg_temp.ok(exists (select 1 from audit.events where action = 'break_glass' and patient_id = :'PAT'),
  'accès d''urgence journalisé');

-- --------------------------------------------- journal d'audit
select pg_temp.ok((select count(*) from audit.events where entity = 'medical_records' and new_data is not null) = 0,
  'journal : aucune valeur médicale copiée');
select pg_temp.refused($$update audit.events set reason = 'x'$$, 'journal : modification impossible');
select pg_temp.refused($$delete from audit.events$$, 'journal : suppression impossible');
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select pg_temp.refused($$select count(*) from audit.events$$, 'utilisateur : pas d''accès direct au journal');
select pg_temp.refused($$select private.wallet_move('00000000-0000-0000-0000-00000000000a', 'topup', 100000)$$,
  'utilisateur : fonctions internes non exécutables');
select pg_temp.refused($$select public.bootstrap_staff('00000000-0000-0000-0000-00000000000a', '{finance}')$$,
  'utilisateur : ne peut pas se promouvoir admin');
reset role;

-- ---------------------------------- réclamations, retraits, avis
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select public.open_complaint('20000000-0000-0000-0000-000000000001', 'delay', 'Arrivée avec 45 minutes de retard.')
  as complaint_id \gset
reset role;
select set_config('request.jwt.claim.sub', :'O', false); set role authenticated;
select pg_temp.ok((select count(*) from public.complaints) = 0, 'inconnu : ne voit pas les réclamations');
reset role;
select set_config('request.jwt.claim.sub', :'Y', false); set role authenticated;
select pg_temp.refused(format($$select public.admin_update_complaint(%L, 'resolved', 'Remboursement partiel', 2000)$$, :'complaint_id'),
  'support sans finance : pas de remboursement');
select public.admin_update_complaint(:'complaint_id', 'resolved', 'Excuses présentées, soignante avertie.');
reset role;

select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
select balance as before_balance from public.wallets where owner_id = :'A' \gset
select public.request_withdrawal(1000, 'wave', '0700000000');
reset role;
select set_config('request.jwt.claim.sub', :'X', false); set role authenticated;
select public.admin_settle_withdrawal(id, false, null, 'Numéro invalide') from public.withdrawals where pro_id = :'A';
reset role;
select pg_temp.ok((select balance from public.wallets where owner_id = :'A') = :before_balance,
  'retrait échoué : montant recrédité');

select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
insert into public.reviews (booking_id, pro_id, rating, comment)
values ('20000000-0000-0000-0000-000000000001', :'A', 1, 'Propos injurieux');
reset role;
select set_config('request.jwt.claim.sub', :'X', false); set role authenticated;
select public.admin_hide_review('20000000-0000-0000-0000-000000000001', true, 'Propos injurieux');
reset role;
select set_config('request.jwt.claim.sub', :'O', false); set role authenticated;
select pg_temp.ok((select count(*) from public.reviews) = 0, 'avis masqué invisible du public');
reset role;
select pg_temp.ok((select rating_count from public.pros where id = :'A') = 0, 'note recalculée sans l''avis masqué');

-- ------------------------------------------------- disponibilités
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
insert into public.availability_rules (pro_id, weekday, start_time, end_time)
select :'B', d, '08:00', '12:00' from generate_series(1, 7) d;
reset role;
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select pg_temp.refused($$insert into public.bookings (booked_by, patient_id, pro_id, service_id, commune, address, scheduled_at)
  values ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b1',
  'pansement', 'Cocody', 'Cocody Angré 8e tranche',
  date_trunc('day', now() at time zone 'Africa/Abidjan' + interval '2 days') + interval '15 hours')$$,
  'réservation hors des disponibilités');
insert into public.bookings (booked_by, patient_id, pro_id, service_id, commune, address, scheduled_at)
values (:'P', :'PAT', :'B', 'pansement', 'Cocody', 'Cocody Angré 8e tranche',
        date_trunc('day', now() at time zone 'Africa/Abidjan' + interval '2 days') + interval '9 hours');
reset role;
select pg_temp.ok(true, 'réservation dans les disponibilités');

-- ----------------------------- proche retiré par le titulaire
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select public.revoke_patient_member(id) from public.patient_members where member_id = :'F';
reset role;
select set_config('request.jwt.claim.sub', :'F', false); set role authenticated;
select pg_temp.ok((select count(*) from public.medical_records) = 0, 'proche retiré : plus d''accès au dossier');
reset role;


-- ------------------------------------------------------ Pro Premium
select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
select public.subscribe_premium();
select pg_temp.ok((select count(*) from public.subscriptions where source = 'paid') = 1,
  'Pro Premium : période enregistrée dans subscriptions');
reset role;


-- ===================================================== 0012 · espace soignant
-- Pièce expirée : plus de demande, ni dans la recherche, ni à la réservation.
update public.pro_documents set expires_on = current_date - 1
  where pro_id = :'A' and doc_type = 'rc_pro';
select pg_temp.ok(not private.pro_is_active(:'A'), 'soignant : pièce expirée = inactif');
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select pg_temp.ok(not exists (select 1 from public.search_pros('pansement', 'Cocody') where id = :'A'),
  'recherche : soignant à pièce expirée absent');
select pg_temp.refused($$insert into public.bookings (booked_by, patient_id, pro_id, service_id, commune, address, scheduled_at)
  values ('00000000-0000-0000-0000-00000000000a', '10000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a1',
  'pansement', 'Cocody', 'Cocody Angré 8e tranche', now() + interval '3 days')$$, 'réservation chez un soignant à pièce expirée');
reset role;
select pg_temp.ok(public.expire_pro_documents() = 1, 'tâche quotidienne : dossier passé en « expiré »');
select pg_temp.ok((select verification_status::text from public.pros where id = :'A') = 'expired', 'statut expiré');
-- Renouvellement par le soignant, puis contrôle.
select set_config('request.jwt.claim.sub', :'A', false); set role authenticated;
insert into public.pro_documents (pro_id, doc_type, storage_path, expires_on)
  values (:'A', 'rc_pro', :'A' || '/rc_pro_2.pdf', current_date + 365);
select pg_temp.ok(public.submit_pro_dossier() = 'under_review', 'pièce renouvelée : dossier en examen');
reset role;
select set_config('request.jwt.claim.sub', :'X', false); set role authenticated;
select public.admin_verify_pro(:'A');
reset role;
select pg_temp.ok(private.pro_is_active(:'A'), 'contrôlé : de nouveau actif');

-- Dossier incomplet : pas de file de vérification.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'moussa@test.ci', '{"role":"pro","full_name":"Moussa Diallo"}');
select set_config('request.jwt.claim.sub', '00000000-0000-0000-0000-0000000000e1', false); set role authenticated;
insert into public.pros (id, display_name, pro_type, communes)
  values ('00000000-0000-0000-0000-0000000000e1', 'Moussa Diallo', 'aide_soignant', '{Cocody}');
insert into public.pro_documents (pro_id, doc_type, storage_path)
  values ('00000000-0000-0000-0000-0000000000e1', 'diplome', '00000000-0000-0000-0000-0000000000e1/diplome.pdf');
select pg_temp.ok(public.submit_pro_dossier() = 'incomplete', 'pièces manquantes : dossier incomplet');
select pg_temp.refused($$insert into public.pro_services (pro_id, service_id, price)
  values ('00000000-0000-0000-0000-0000000000e1', 'injection', 6000)$$, 'aide-soignant : injection hors de ses actes');
reset role;
select set_config('request.jwt.claim.sub', :'X', false); set role authenticated;
select pg_temp.refused($$select public.admin_start_review('00000000-0000-0000-0000-0000000000e1')$$,
  'dossier incomplet : pas d''examen');
reset role;
select pg_temp.ok(not private.vital_in_scope('aide_soignant', 'glycemia')
  and private.vital_in_scope('aide_soignant', 'temperature')
  and private.vital_in_scope('infirmier', 'glycemia'), 'champ d''exercice : constantes par profession');

-- Refus motivé (Serge : disponible 8 h – 12 h).
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
insert into public.bookings (id, booked_by, patient_id, pro_id, service_id, commune, address, scheduled_at)
values ('20000000-0000-0000-0000-0000000000b2', :'P', :'PAT', :'B', 'pansement', 'Cocody', 'Cocody Angré 8e tranche',
        date_trunc('day', now() at time zone 'Africa/Abidjan' + interval '4 days') + interval '10 hours');
reset role;
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
select public.refuse_booking('20000000-0000-0000-0000-0000000000b2', 'Trop loin de ma zone');
reset role;
select pg_temp.ok((select status::text || '|' || refusal_reason from public.bookings
  where id = '20000000-0000-0000-0000-0000000000b2') = 'refused|Trop loin de ma zone', 'refus motivé enregistré');

-- Journal de visite : « en route » prévient la famille.
select id as visit from public.bookings where pro_id = :'B' and status = 'pending' and patient_id = :'PAT'
  order by created_at limit 1 \gset
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
select public.respond_booking(:'visit', true);
reset role;
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select public.pay_booking_with_wallet(:'visit');
reset role;
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
select pg_temp.refused(format($$select public.add_care_journal(%L, 'on_the_way')$$, :'visit'),
  'journal : « en route » trop tôt refusé');
reset role;
update public.bookings set scheduled_at = now() + interval '40 minutes',
  slot = tstzrange(now() + interval '40 minutes', now() + interval '85 minutes') where id = :'visit';
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
select public.add_care_journal(:'visit', 'on_the_way');
reset role;
select pg_temp.ok(exists (select 1 from public.notifications
  where user_id = :'P' and booking_id = :'visit' and title = 'Serge Aka est en route'),
  'journal : la famille sait que le soignant est en route');
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select pg_temp.ok((select count(*) from public.care_journal_entries) = 1, 'journal visible par la famille');
select pg_temp.refused($$select public.report_incident(null, 'other', 'Je ne suis pas soignant du tout.')$$,
  'incident : réservé aux soignants');
reset role;

-- Incident grave signalé par le soignant.
select set_config('request.jwt.claim.sub', :'B', false); set role authenticated;
select public.report_incident(:'visit', 'insecurity', 'Menaces d''un voisin à mon arrivée.');
reset role;
select pg_temp.ok(exists (select 1 from public.notifications
  where user_id = :'X' and title = 'Urgent : incident signalé'), 'incident grave : l''équipe est alertée');
select set_config('request.jwt.claim.sub', :'O', false); set role authenticated;
select pg_temp.ok((select count(*) from public.incident_reports) = 0, 'incident : invisible pour les autres');
reset role;


-- ================================================= 0013 · console admin
select set_config('request.jwt.claim.sub', :'P', false); set role authenticated;
select pg_temp.refused($$select public.admin_dashboard_context()$$, 'console : réservée à l''équipe');
reset role;
select set_config('request.jwt.claim.sub', :'X', false); set role authenticated;
select pg_temp.ok((public.admin_dashboard_context() ->> 'patients')::int >= 1
  and public.admin_dashboard_context() -> 'permissions' ? 'finance', 'console : comptages et permissions');
select pg_temp.ok((select count(*) from public.patients) = 0, 'console : aucune lecture directe des patients');
select public.admin_refund_booking('20000000-0000-0000-0000-000000000001', 2000, 'Retard important');
select pg_temp.refused($$select public.admin_refund_booking('20000000-0000-0000-0000-000000000001', 7000, 'Trop élevé')$$,
  'remboursement plafonné au montant payé');
select public.admin_cancel_booking(:'visit', 'Soignant indisponible');
select pg_temp.ok(public.admin_broadcast('pros', 'Formation', 'Atelier samedi matin.') >= 1, 'message aux soignants');
reset role;
select pg_temp.ok((select admin_refunded from public.bookings where id = '20000000-0000-0000-0000-000000000001') = 2000,
  'remboursement partiel enregistré');
select pg_temp.ok((select status::text from public.bookings where id = :'visit') = 'cancelled',
  'annulation par l''équipe');
select set_config('request.jwt.claim.sub', :'Y', false); set role authenticated;
select pg_temp.refused($$select public.admin_refund_booking('20000000-0000-0000-0000-000000000001', 100, 'Geste commercial')$$,
  'support sans finance : pas de remboursement');
select public.admin_update_incident(id, 'closed', 'Voisinage averti, accompagnement prévu.') from public.incident_reports limit 1;
reset role;
select pg_temp.ok((select status from public.incident_reports limit 1) = 'closed', 'incident clos par le support');
select pg_temp.ok(exists (select 1 from audit.events where action in ('admin_refund', 'admin_cancel', 'admin_broadcast')),
  'actions de l''équipe journalisées');

\echo 'Scénario de sécurité : tous les contrôles sont passés.'
