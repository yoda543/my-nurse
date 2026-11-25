-- Retour arrière de 0009_access_control.sql. À exécuter dans une transaction,
-- après 0010_down.sql.
-- Données perdues : staff_permissions, patient_members (les proches perdent
-- leur accès), record_access_grants.
-- Volontairement conservés :
--   * le schéma audit et son journal (preuve légale, ajout seul) ;
--   * le retrait du droit d'exécution public sur les fonctions de private
--     (durcissement sans effet sur l'app). Pour revenir exactement à l'état
--     antérieur : grant execute on all functions in schema private to public;

-- Garde-fou : ne s'exécute que si on le confirme explicitement dans la session :
--   set mynurse.confirm_rollback = 'yes';
-- AVANT : exporter les tables listées ci-dessous (pg_dump --data-only -t …).
do $$
begin
  if current_setting('mynurse.confirm_rollback', true) is distinct from 'yes' then
    raise exception 'Retour arrière non confirmé (set mynurse.confirm_rollback = yes).';
  end if;
end $$;

-- Règles d'accès remises dans leur version précédente.
drop policy if exists patients_member on public.patients;
drop policy if exists bookings_member on public.bookings;
drop policy if exists bookings_insert on public.bookings;
drop policy if exists bookings_select on public.bookings;
drop policy if exists contracts_select on public.contracts;
drop policy if exists pro_documents_select on public.pro_documents;
drop policy if exists pro_documents_read on storage.objects;
drop policy if exists pro_cancellations_select on public.pro_cancellations;
drop policy if exists wallets_select on public.wallets;
drop policy if exists wallet_transactions_select on public.wallet_transactions;
drop policy if exists withdrawals_select on public.withdrawals;
drop policy if exists profiles_select on public.profiles;
drop policy if exists care_logs_select on public.care_logs;
create policy bookings_insert on public.bookings as PERMISSIVE for INSERT to authenticated
  with check (((booked_by = ( SELECT auth.uid() AS uid)) AND private.owns_patient(patient_id)));
create policy bookings_select on public.bookings as PERMISSIVE for SELECT to authenticated
  using (((booked_by = ( SELECT auth.uid() AS uid)) OR (pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin)));
create policy care_logs_select on public.care_logs as PERMISSIVE for SELECT to authenticated
  using ((EXISTS ( SELECT 1
   FROM bookings b
  WHERE ((b.id = care_logs.booking_id) AND ((b.booked_by = ( SELECT auth.uid() AS uid)) OR (b.pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin))))));
create policy contracts_select on public.contracts as PERMISSIVE for SELECT to authenticated
  using (((booked_by = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin) OR (EXISTS ( SELECT 1
   FROM bookings b
  WHERE ((b.contract_id = contracts.id) AND (b.pro_id = ( SELECT auth.uid() AS uid)))))));
create policy pro_documents_read on storage.objects as PERMISSIVE for SELECT to authenticated
  using (((bucket_id = 'pro-documents'::text) AND (((storage.foldername(name))[1] = (( SELECT auth.uid() AS uid))::text) OR ( SELECT private.is_admin() AS is_admin))));
create policy pro_cancellations_select on public.pro_cancellations as PERMISSIVE for SELECT to authenticated
  using (((pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin)));
create policy pro_documents_select on public.pro_documents as PERMISSIVE for SELECT to authenticated
  using (((pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin)));
create policy profiles_select on public.profiles as PERMISSIVE for SELECT to authenticated
  using (((id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin)));
create policy wallet_transactions_select on public.wallet_transactions as PERMISSIVE for SELECT to authenticated
  using (((owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin)));
create policy wallets_select on public.wallets as PERMISSIVE for SELECT to authenticated
  using (((owner_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin)));
create policy withdrawals_select on public.withdrawals as PERMISSIVE for SELECT to authenticated
  using (((pro_id = ( SELECT auth.uid() AS uid)) OR ( SELECT private.is_admin() AS is_admin)));

-- Fonctions d'administration remises dans leur version précédente (0001, 0004).
CREATE OR REPLACE FUNCTION public.admin_reject_pro(p_pro uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.require_admin();
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

CREATE OR REPLACE FUNCTION public.admin_suspend_pro(p_pro uuid, p_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_id uuid;
begin
  perform private.require_admin();
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
$function$
;

CREATE OR REPLACE FUNCTION public.admin_reliability_alerts()
 RETURNS TABLE(pro_id uuid, display_name text, cancellations bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  perform private.require_admin();
  return query
    select p.id, p.display_name, count(*)
    from public.pro_cancellations c join public.pros p on p.id = c.pro_id
    where c.created_at > now() - interval '30 days'
    group by p.id, p.display_name
    having count(*) >= 2;
end;
$function$
;

-- Notifications : version de 0007 (sans copie à la famille).
CREATE OR REPLACE FUNCTION private.notify(p_user uuid, p_title text, p_body text, p_booking uuid DEFAULT NULL::uuid)
 RETURNS void
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
  insert into public.notifications (user_id, title, body, booking_id)
  select p_user, p_title, p_body, p_booking where p_user is not null;
$function$
;

drop trigger if exists bookings_sync_grant on public.bookings;
drop trigger if exists patients_audit on public.patients;
drop trigger if exists care_logs_audit on public.care_logs;
drop trigger if exists pros_audit on public.pros;
drop trigger if exists pro_documents_audit on public.pro_documents;
drop trigger if exists profiles_role_audit on public.profiles;
drop trigger if exists withdrawals_audit on public.withdrawals;

drop function if exists public.admin_set_staff_permission(uuid, public.staff_permission, boolean);
drop function if exists public.bootstrap_staff(uuid, public.staff_permission[]);
drop function if exists public.grant_record_access(uuid, uuid, public.record_scope[], timestamptz, text);
drop function if exists public.revoke_record_access(uuid, text);
drop function if exists public.admin_break_glass(uuid, text);
drop function if exists public.add_patient_member(uuid, text, public.member_relation, public.member_permission[], timestamptz, text, text);
drop function if exists public.my_shared_patients();
drop function if exists public.update_patient_member(uuid, public.member_permission[], timestamptz);
drop function if exists public.revoke_patient_member(uuid);
drop function if exists public.my_record_access_log(uuid, int);
drop function if exists public.admin_audit_events(uuid, uuid, text, timestamptz, int);
drop function if exists private.sync_booking_grant();

drop table if exists public.record_access_grants, public.patient_members, public.staff_permissions;
drop function if exists private.has_record_access(uuid, public.record_scope), private.can_act_for(uuid, public.member_permission),
  private.member_has(uuid, public.member_permission), private.is_member(uuid),
  private.require_perm(public.staff_permission), private.has_perm(public.staff_permission),
  private.has_any_perm(public.staff_permission[]);
drop type if exists public.record_scope, public.member_permission, public.member_relation, public.staff_permission;
