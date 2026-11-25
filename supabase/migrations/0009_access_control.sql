-- 0009 · Contrôle d'accès : permissions du personnel, proches et aidants,
-- accès temporaires et révocables au dossier médical, journal d'audit.
--
-- Migration purement additive : aucune table, colonne ni donnée supprimée.
-- Les règles d'accès existantes sont remplacées par des règles plus strictes
-- (drop policy + create policy dans la même transaction).

-- ============================================================ journal d'audit
-- Schéma non exposé par l'API. Lecture uniquement via des fonctions contrôlées.
-- Idempotent : le journal est conservé si on revient en arrière puis qu'on
-- réapplique cette migration.
create schema if not exists audit;
revoke all on schema audit from public, anon, authenticated;

create table if not exists audit.events (
  id bigint generated always as identity primary key,
  occurred_at timestamptz not null default now(),
  actor_id uuid,                    -- auth.uid() ; null = serveur, cron, webhook
  actor_role text,                  -- rôle applicatif (patient, pro, admin) ou rôle base
  action text not null,             -- insert, update, delete, read, grant, revoke, break_glass…
  entity text not null,             -- table ou objet métier
  entity_id text,
  patient_id uuid,                  -- renseigné pour toute donnée de santé
  changed_fields text[],
  old_data jsonb,                   -- jamais rempli pour les données de santé
  new_data jsonb,                   -- idem : seuls les noms de champs sont gardés
  reason text
);
-- Pas de clé étrangère : le journal doit survivre à la suppression d'un compte.
create index if not exists audit_events_patient_idx on audit.events (patient_id, occurred_at desc) where patient_id is not null;
create index if not exists audit_events_actor_idx on audit.events (actor_id, occurred_at desc);
create index if not exists audit_events_entity_idx on audit.events (entity, entity_id);

-- Journal en ajout seul : ni modification ni suppression, même par le serveur.
create or replace function audit.forbid_change() returns trigger
language plpgsql set search_path = '' as $$
begin
  raise exception 'Le journal d''audit ne se modifie pas.';
end;
$$;
drop trigger if exists events_append_only on audit.events;
create trigger events_append_only before update or delete on audit.events
  for each row execute function audit.forbid_change();
drop trigger if exists events_no_truncate on audit.events;
create trigger events_no_truncate before truncate on audit.events
  for each statement execute function audit.forbid_change();

create or replace function audit.current_role() returns text
language sql stable security definer set search_path = '' as $$
  select coalesce(
    (select role::text from public.profiles where id = (select auth.uid())),
    current_user::text);
$$;

-- Écriture explicite depuis une fonction (lecture de dossier, accès d'urgence…).
create or replace function audit.log(
  p_action text, p_entity text, p_entity_id text,
  p_patient uuid default null, p_reason text default null, p_data jsonb default null
) returns void
language sql security definer set search_path = '' as $$
  insert into audit.events (actor_id, actor_role, action, entity, entity_id, patient_id, reason, new_data)
  values ((select auth.uid()), audit.current_role(), p_action, p_entity, p_entity_id, p_patient, p_reason, p_data);
$$;

-- Déclencheur générique.
--   TG_ARGV[0] : 'phi' (donnée de santé : on garde seulement les noms des
--                champs modifiés) ou 'full' (on garde l'ancien et le nouvel état).
--   TG_ARGV[1] : nom de la colonne qui porte l'identifiant du patient (optionnel).
--   TG_ARGV[2] : nom de la colonne identifiant (défaut : id).
create or replace function audit.log_change() returns trigger
language plpgsql security definer set search_path = '' as $$
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

-- ================================================== permissions du personnel
-- Le rôle 'admin' de profiles ne donne plus tout : chaque action
-- d'administration exige une permission précise (moindre privilège).
-- 'medical_break_glass' n'est attribuée à personne par défaut.
create type public.staff_permission as enum (
  'verify_pros',          -- dossiers des soignants, pièces justificatives
  'manage_bookings',      -- rendez-vous, suivis, fiabilité
  'finance',              -- paiements, portefeuilles, retraits, commissions
  'support',              -- comptes, réclamations
  'moderate',             -- avis
  'audit_read',           -- lecture du journal d'audit
  'manage_settings',      -- paramètres, pharmacies, catalogue
  'manage_staff',         -- attribution des permissions
  'medical_break_glass'   -- accès d'urgence à un dossier médical, tracé et notifié
);

create table public.staff_permissions (
  profile_id uuid not null references public.profiles on delete cascade,
  permission public.staff_permission not null,
  granted_by uuid references public.profiles on delete set null,
  granted_at timestamptz not null default now(),
  primary key (profile_id, permission)
);
create index staff_permissions_granted_by_idx on public.staff_permissions (granted_by);

-- Reprise : les administrateurs actuels gardent ce qu'ils pouvaient déjà faire,
-- sans l'accès d'urgence au dossier médical (qu'ils n'avaient pas).
insert into public.staff_permissions (profile_id, permission)
select p.id, perm
from public.profiles p
cross join unnest(enum_range(null::public.staff_permission)) perm
where p.role = 'admin' and perm <> 'medical_break_glass'
on conflict do nothing;

create function private.has_perm(p_perm public.staff_permission) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_permissions sp
    join public.profiles p on p.id = sp.profile_id
    where sp.profile_id = (select auth.uid()) and p.role = 'admin' and sp.permission = p_perm
  );
$$;

create function private.has_any_perm(p_perms public.staff_permission[]) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.staff_permissions sp
    join public.profiles p on p.id = sp.profile_id
    where sp.profile_id = (select auth.uid()) and p.role = 'admin' and sp.permission = any (p_perms)
  );
$$;

create function private.require_perm(p_perm public.staff_permission) returns void
language plpgsql stable security definer set search_path = '' as $$
begin
  if not private.has_perm(p_perm) then
    raise exception 'Action réservée (permission % requise).', p_perm;
  end if;
end;
$$;

-- Attribution / retrait d'une permission. Personne ne peut s'attribuer
-- lui-même l'accès d'urgence au dossier médical (règle des deux personnes).
create function public.admin_set_staff_permission(
  p_profile uuid, p_perm public.staff_permission, p_grant boolean
) returns void
language plpgsql security definer set search_path = '' as $$
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

-- Amorçage d'un compte de l'équipe (premier admin, ou nouvel arrivant).
-- Réservée au serveur : éditeur SQL du tableau de bord ou clé service.
-- Donne les permissions demandées, jamais l'accès d'urgence (qui exige
-- un second administrateur, voir admin_set_staff_permission).
--   select public.bootstrap_staff('<uuid>', '{verify_pros,manage_bookings,finance,support,moderate,audit_read,manage_settings,manage_staff}');
create function public.bootstrap_staff(p_profile uuid, p_perms public.staff_permission[]) returns void
language plpgsql security definer set search_path = '' as $$
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
revoke execute on function public.bootstrap_staff(uuid, public.staff_permission[]) from public, anon, authenticated;
grant execute on function public.bootstrap_staff(uuid, public.staff_permission[]) to service_role;

-- ==================================================== proches et aidants
-- patients.owner_id reste le titulaire (le compte qui a créé la fiche) ;
-- il contrôle seul qui d'autre y accède, et avec quels droits.
create type public.member_relation as enum ('family', 'caregiver', 'guardian');
create type public.member_permission as enum (
  'view_records',     -- lire le dossier médical
  'manage_records',   -- modifier le dossier, ajouter des documents
  'book_care',        -- réserver et payer des soins pour ce patient
  'view_reports'      -- lire les rendez-vous et comptes rendus de soin
);

create table public.patient_members (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients on delete cascade,
  member_id uuid not null references public.profiles on delete cascade,
  relation public.member_relation not null,
  permissions public.member_permission[] not null default '{view_reports}',
  invited_by uuid not null references public.profiles on delete cascade,
  expires_at timestamptz,
  revoked_at timestamptz,
  revoked_by uuid references public.profiles on delete set null,
  created_at timestamptz not null default now(),
  -- Affichage côté titulaire (il ne lit pas le profil du proche) :
  -- nom donné à l'invitation, lien (« Fils »), contact masqué.
  display_name text not null default '' check (length(display_name) <= 80),
  relation_label text not null default '' check (length(relation_label) <= 40),
  contact_hint text not null default '' check (length(contact_hint) <= 40),
  check (cardinality(permissions) > 0),
  check (expires_at is null or expires_at > created_at)
);
create unique index patient_members_active_idx on public.patient_members (patient_id, member_id)
  where revoked_at is null;
create index patient_members_member_idx on public.patient_members (member_id) where revoked_at is null;
create index patient_members_invited_by_idx on public.patient_members (invited_by);

create function private.member_has(p_patient uuid, p_perm public.member_permission) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.patient_members m
    where m.patient_id = p_patient and m.member_id = (select auth.uid())
      and m.revoked_at is null and (m.expires_at is null or m.expires_at > now())
      and p_perm = any (m.permissions)
  );
$$;

create function private.is_member(p_patient uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.patient_members m
    where m.patient_id = p_patient and m.member_id = (select auth.uid())
      and m.revoked_at is null and (m.expires_at is null or m.expires_at > now())
  );
$$;

-- Titulaire, ou proche disposant de la permission demandée.
create function private.can_act_for(p_patient uuid, p_perm public.member_permission) returns boolean
language sql stable security definer set search_path = '' as $$
  select private.owns_patient(p_patient) or private.member_has(p_patient, p_perm);
$$;

-- ======================================= accès temporaires au dossier médical
create type public.record_scope as enum (
  'summary',     -- identité, allergies, traitements, antécédents
  'vitals',      -- constantes
  'documents',   -- ordonnances, résultats, comptes rendus
  'reports',     -- comptes rendus de soin des autres soignants
  'full'         -- tout ce qui précède
);

create table public.record_access_grants (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients on delete cascade,
  grantee_id uuid not null references public.profiles on delete cascade,
  scopes public.record_scope[] not null,
  source text not null check (source in ('booking', 'patient', 'break_glass')),
  booking_id uuid references public.bookings on delete cascade,
  reason text not null default '',
  granted_by uuid references public.profiles on delete set null,
  starts_at timestamptz not null default now(),
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_by uuid references public.profiles on delete set null,
  revoke_reason text,
  created_at timestamptz not null default now(),
  check (cardinality(scopes) > 0),
  check (expires_at > starts_at),
  check (source <> 'booking' or booking_id is not null),
  check (source <> 'break_glass' or length(trim(reason)) >= 10),
  check (source <> 'break_glass' or expires_at <= starts_at + interval '4 hours'),
  check (expires_at <= starts_at + interval '366 days')
);
create index record_access_grants_lookup_idx on public.record_access_grants (grantee_id, patient_id)
  where revoked_at is null;
create index record_access_grants_patient_idx on public.record_access_grants (patient_id, created_at desc);
create unique index record_access_grants_booking_idx on public.record_access_grants (booking_id)
  where source = 'booking';

-- Droit de lire une partie du dossier : titulaire, proche autorisé, ou
-- accès temporaire en cours (non révoqué, non expiré) couvrant ce périmètre.
create function private.has_record_access(p_patient uuid, p_scope public.record_scope) returns boolean
language sql stable security definer set search_path = '' as $$
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

-- Accès lié à une réservation : créé à la demande (identité et allergies,
-- pour décider), élargi à l'acceptation, retiré si le soin est refusé ou
-- annulé, expire 24 h après la fin prévue du soin (temps du compte rendu).
create function private.sync_booking_grant() returns trigger
language plpgsql security definer set search_path = '' as $$
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
create trigger bookings_sync_grant after insert or update of status on public.bookings
  for each row execute function private.sync_booking_grant();

-- Reprise : accès pour les réservations en cours au moment de la migration.
insert into public.record_access_grants (patient_id, grantee_id, scopes, source, booking_id, reason, starts_at, expires_at)
select b.patient_id, b.pro_id,
       case when b.status = 'accepted' then '{summary,vitals,documents,reports}'::public.record_scope[]
            else '{summary}'::public.record_scope[] end,
       'booking', b.id, 'Reprise 0009', least(b.created_at, now()),
       greatest(coalesce(upper(b.slot), b.scheduled_at + interval '2 hours') + interval '24 hours',
                least(b.created_at, now()) + interval '1 minute')
from public.bookings b
where b.status in ('pending', 'accepted')
on conflict (booking_id) where source = 'booking' do nothing;

-- Le titulaire accorde un accès à un soignant vérifié (ex. son médecin traitant).
create function public.grant_record_access(
  p_patient uuid, p_pro uuid, p_scopes public.record_scope[], p_expires_at timestamptz,
  p_reason text default ''
) returns uuid
language plpgsql security definer set search_path = '' as $$
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

-- Révocation immédiate : par le titulaire (n'importe quel accès, y compris
-- celui d'une réservation) ou par le bénéficiaire qui y renonce.
create function public.revoke_record_access(p_grant uuid, p_reason text default '') returns void
language plpgsql security definer set search_path = '' as $$
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

-- Accès d'urgence (« bris de glace ») : 4 h maximum, motif obligatoire,
-- tracé dans le journal et notifié immédiatement au titulaire.
create function public.admin_break_glass(p_patient uuid, p_reason text) returns uuid
language plpgsql security definer set search_path = '' as $$
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

-- ---------------------------------------------- gestion des proches (RPC)
create function public.add_patient_member(
  p_patient uuid, p_contact text, p_relation public.member_relation,
  p_permissions public.member_permission[], p_expires_at timestamptz default null,
  p_display_name text default '', p_relation_label text default ''
) returns uuid
language plpgsql security definer set search_path = '' as $$
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
  insert into public.patient_members (patient_id, member_id, relation, permissions, invited_by, expires_at,
                                      display_name, relation_label, contact_hint)
    values (p_patient, v_member, p_relation, p_permissions, (select auth.uid()), p_expires_at,
            left(trim(coalesce(p_display_name, '')), 80), left(trim(coalesce(p_relation_label, '')), 40),
            -- Contact masqué : seuls les 4 derniers caractères restent lisibles.
            '…' || right(trim(p_contact), 4))
    returning id into v_id;
  perform private.notify(v_member, 'Accès au dossier d''un proche',
    (select coalesce(nullif(full_name, ''), 'Un proche') from public.profiles where id = (select auth.uid()))
    || ' vous a ajouté pour ' || (select full_name from public.patients where id = p_patient) || '.');
  return v_id;
end;
$$;

create function public.update_patient_member(
  p_member uuid, p_permissions public.member_permission[], p_expires_at timestamptz default null
) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.patient_members m set permissions = p_permissions, expires_at = p_expires_at
    where m.id = p_member and m.revoked_at is null and private.owns_patient(m.patient_id);
  if not found then
    raise exception 'Proche introuvable.';
  end if;
end;
$$;

-- Le titulaire retire un proche ; un proche peut aussi se retirer lui-même.
create function public.revoke_patient_member(p_member uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.patient_members m set revoked_at = now(), revoked_by = (select auth.uid())
    where m.id = p_member and m.revoked_at is null
      and (private.owns_patient(m.patient_id) or m.member_id = (select auth.uid()));
  if not found then
    raise exception 'Proche introuvable.';
  end if;
end;
$$;

-- Dossiers confiés au compte connecté, avec le nom du titulaire et ses
-- droits (le proche ne peut pas lire le profil du titulaire).
create function public.my_shared_patients()
returns table (member_id uuid, patient_id uuid, owner_name text,
               permissions public.member_permission[], expires_at timestamptz)
language sql stable security definer set search_path = '' as $$
  select m.id, m.patient_id, coalesce(nullif(pr.full_name, ''), 'Le titulaire'), m.permissions, m.expires_at
  from public.patient_members m
  join public.patients pa on pa.id = m.patient_id
  join public.profiles pr on pr.id = pa.owner_id
  where m.member_id = (select auth.uid())
    and m.revoked_at is null and (m.expires_at is null or m.expires_at > now());
$$;

-- Notifications de soin : quand le serveur prévient celui qui a réservé,
-- il prévient aussi le titulaire du dossier et les proches qui suivent
-- les soins de ce patient. Même signature que 0007 ; un seul point de
-- passage pour toutes les notifications de réservation.
create or replace function private.notify(p_user uuid, p_title text, p_body text, p_booking uuid default null)
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_patient uuid;
  v_booker uuid;
begin
  if p_user is null then
    return;
  end if;
  insert into public.notifications (user_id, title, body, booking_id)
    values (p_user, p_title, p_body, p_booking);
  if p_booking is null then
    return;
  end if;
  select patient_id, booked_by into v_patient, v_booker from public.bookings where id = p_booking;
  if v_booker is distinct from p_user then
    return;  -- notification destinée au soignant : pas de copie à la famille
  end if;
  insert into public.notifications (user_id, title, body, booking_id)
  select distinct r.uid, p_title, p_body, p_booking
  from (
    select owner_id as uid from public.patients where id = v_patient
    union
    select m.member_id from public.patient_members m
    where m.patient_id = v_patient and m.revoked_at is null
      and (m.expires_at is null or m.expires_at > now())
      and (m.permissions && '{view_reports,book_care}'::public.member_permission[])
  ) r
  where r.uid is distinct from p_user;
end;
$$;

-- ------------------------------------------------ lecture du journal (RPC)
-- Le titulaire voit qui a accédé au dossier de ses patients.
create function public.my_record_access_log(p_patient uuid, p_limit int default 100)
returns table (occurred_at timestamptz, actor_name text, actor_role text, action text,
               entity text, reason text)
language plpgsql stable security definer set search_path = '' as $$
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

create function public.admin_audit_events(
  p_patient uuid default null, p_actor uuid default null, p_entity text default null,
  p_since timestamptz default now() - interval '30 days', p_limit int default 200
) returns setof audit.events
language plpgsql stable security definer set search_path = '' as $$
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

-- ================================================ règles d'accès (RLS)
alter table public.staff_permissions enable row level security;
alter table public.patient_members enable row level security;
alter table public.record_access_grants enable row level security;

revoke all on public.staff_permissions, public.patient_members, public.record_access_grants
  from anon, authenticated;
-- Lecture seule : toute écriture passe par les fonctions ci-dessus.
grant select on public.staff_permissions, public.patient_members, public.record_access_grants
  to authenticated;

create policy staff_permissions_select on public.staff_permissions for select to authenticated
  using (profile_id = (select auth.uid()) or (select private.has_perm('manage_staff')));

create policy patient_members_select on public.patient_members for select to authenticated
  using (member_id = (select auth.uid()) or (select private.owns_patient(patient_id)));

create policy record_access_grants_select on public.record_access_grants for select to authenticated
  using (grantee_id = (select auth.uid())
    or (select private.owns_patient(patient_id))
    or (select private.has_perm('audit_read')));

-- Proches : ils voient la fiche (identité) du patient dont ils sont membres.
create policy patients_member on public.patients for select to authenticated
  using ((select private.is_member(id)));

-- Réservation pour un proche : titulaire ou proche autorisé à réserver.
drop policy bookings_insert on public.bookings;
create policy bookings_insert on public.bookings for insert to authenticated
  with check (
    booked_by = (select auth.uid())
    and (select private.can_act_for(patient_id, 'book_care'))
  );

-- Les proches autorisés suivent les rendez-vous du patient.
create policy bookings_member on public.bookings for select to authenticated
  using ((select private.member_has(patient_id, 'view_reports'))
      or (select private.member_has(patient_id, 'book_care')));

-- Personnel : chaque table d'administration exige sa permission.
drop policy bookings_select on public.bookings;
create policy bookings_select on public.bookings for select to authenticated
  using (booked_by = (select auth.uid()) or pro_id = (select auth.uid())
    or (select private.has_any_perm('{manage_bookings,support,finance}')));

drop policy contracts_select on public.contracts;
create policy contracts_select on public.contracts for select to authenticated
  using (booked_by = (select auth.uid())
    or (select private.has_any_perm('{manage_bookings,support}'))
    or exists (select 1 from public.bookings b where b.contract_id = contracts.id and b.pro_id = (select auth.uid())));

drop policy pro_documents_select on public.pro_documents;
create policy pro_documents_select on public.pro_documents for select to authenticated
  using (pro_id = (select auth.uid()) or (select private.has_perm('verify_pros')));

drop policy pro_documents_read on storage.objects;
create policy pro_documents_read on storage.objects for select to authenticated
  using (bucket_id = 'pro-documents'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select private.has_perm('verify_pros'))));

drop policy pro_cancellations_select on public.pro_cancellations;
create policy pro_cancellations_select on public.pro_cancellations for select to authenticated
  using (pro_id = (select auth.uid()) or (select private.has_any_perm('{verify_pros,manage_bookings}')));

drop policy wallets_select on public.wallets;
create policy wallets_select on public.wallets for select to authenticated
  using (owner_id = (select auth.uid()) or (select private.has_perm('finance')));
drop policy wallet_transactions_select on public.wallet_transactions;
create policy wallet_transactions_select on public.wallet_transactions for select to authenticated
  using (owner_id = (select auth.uid()) or (select private.has_perm('finance')));
drop policy withdrawals_select on public.withdrawals;
create policy withdrawals_select on public.withdrawals for select to authenticated
  using (pro_id = (select auth.uid()) or (select private.has_perm('finance')));

drop policy profiles_select on public.profiles;
create policy profiles_select on public.profiles for select to authenticated
  using (id = (select auth.uid()) or (select private.has_any_perm('{support,verify_pros,finance,manage_staff}')));

-- Comptes rendus de soin : donnée de santé. L'administration n'y a plus
-- accès par défaut (seulement via l'accès d'urgence, voir 0010).
drop policy care_logs_select on public.care_logs;
create policy care_logs_select on public.care_logs for select to authenticated
  using (pro_id = (select auth.uid()) or exists (
    select 1 from public.bookings b
    where b.id = booking_id
      and (b.booked_by = (select auth.uid())
           or (select private.has_record_access(b.patient_id, 'reports')))
  ));

-- ============================================ fonctions d'administration
-- Mêmes fonctions qu'avant (dernière version en production : 0004 / 0001),
-- la permission précise remplace « être admin ».
create or replace function public.admin_reject_pro(p_pro uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
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

create or replace function public.admin_suspend_pro(p_pro uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
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

create or replace function public.admin_reliability_alerts()
returns table (pro_id uuid, display_name text, cancellations bigint)
language plpgsql stable security definer set search_path = '' as $$
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

-- ============================================================ audit : tables
create trigger staff_permissions_audit after insert or update or delete on public.staff_permissions
  for each row execute function audit.log_change('full', '', 'profile_id');
create trigger patient_members_audit after insert or update or delete on public.patient_members
  for each row execute function audit.log_change('full', 'patient_id');
create trigger record_access_grants_audit after insert or update or delete on public.record_access_grants
  for each row execute function audit.log_change('full', 'patient_id');
create trigger patients_audit after insert or update or delete on public.patients
  for each row execute function audit.log_change('phi', 'id');
create trigger care_logs_audit after insert or update or delete on public.care_logs
  for each row execute function audit.log_change('phi', '', 'booking_id');
create trigger pros_audit after update of verification_status, rejection_reason, premium_until on public.pros
  for each row execute function audit.log_change('full');
create trigger pro_documents_audit after insert or delete on public.pro_documents
  for each row execute function audit.log_change('full');
create trigger profiles_role_audit after update of role on public.profiles
  for each row execute function audit.log_change('full');
create trigger withdrawals_audit after insert or update on public.withdrawals
  for each row execute function audit.log_change('full');

-- ========================================================= droits d'exécution
-- Par défaut, PostgreSQL autorise tout le monde (PUBLIC) à exécuter une
-- fonction. On retire ce droit sur tout le schéma private, puis on le rend
-- uniquement aux fonctions utilisées dans les règles d'accès (RLS).
revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on all functions in schema audit from public, anon, authenticated;
grant execute on function
  private.is_admin(), private.require_admin(), private.required_docs(public.pro_type),
  private.owns_patient(uuid), private.treats_patient(uuid),
  private.has_perm(public.staff_permission), private.has_any_perm(public.staff_permission[]),
  private.member_has(uuid, public.member_permission), private.is_member(uuid),
  private.can_act_for(uuid, public.member_permission),
  private.has_record_access(uuid, public.record_scope)
to authenticated;

revoke execute on function
  public.admin_set_staff_permission(uuid, public.staff_permission, boolean),
  public.grant_record_access(uuid, uuid, public.record_scope[], timestamptz, text),
  public.revoke_record_access(uuid, text),
  public.admin_break_glass(uuid, text),
  public.add_patient_member(uuid, text, public.member_relation, public.member_permission[], timestamptz, text, text),
  public.my_shared_patients(),
  public.update_patient_member(uuid, public.member_permission[], timestamptz),
  public.revoke_patient_member(uuid),
  public.my_record_access_log(uuid, int),
  public.admin_audit_events(uuid, uuid, text, timestamptz, int)
from public, anon;
grant execute on function
  public.admin_set_staff_permission(uuid, public.staff_permission, boolean),
  public.grant_record_access(uuid, uuid, public.record_scope[], timestamptz, text),
  public.revoke_record_access(uuid, text),
  public.admin_break_glass(uuid, text),
  public.add_patient_member(uuid, text, public.member_relation, public.member_permission[], timestamptz, text, text),
  public.my_shared_patients(),
  public.update_patient_member(uuid, public.member_permission[], timestamptz),
  public.revoke_patient_member(uuid),
  public.my_record_access_log(uuid, int),
  public.admin_audit_events(uuid, uuid, text, timestamptz, int)
to authenticated;
