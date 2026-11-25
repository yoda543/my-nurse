-- Imitation minimale de l'environnement Supabase pour tester les migrations en local.
do $$ begin if not exists (select from pg_roles where rolname = 'anon') then create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls; end if; end $$;
create schema auth; create schema storage; create schema extensions; create schema cron;
grant usage on schema auth, storage, extensions to anon, authenticated, service_role;
grant usage on schema public to anon, authenticated, service_role;
create table auth.users (id uuid primary key default gen_random_uuid(), email text, phone text,
  raw_user_meta_data jsonb not null default '{}');
create function auth.uid() returns uuid language sql stable as
  $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
create function auth.role() returns text language sql stable as
  $$ select current_setting('role', true) $$;
grant execute on function auth.uid(), auth.role() to anon, authenticated, service_role;
create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint, allowed_mime_types text[]);
create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text references storage.buckets, name text, owner uuid);
alter table storage.objects enable row level security;
grant select, insert, update, delete on storage.objects to authenticated;
create function storage.foldername(name text) returns text[] language sql immutable as
  $$ select (string_to_array(name, '/'))[1:array_length(string_to_array(name, '/'), 1) - 1] $$;
grant execute on function storage.foldername(text) to authenticated;
create function cron.schedule(n text, s text, c text) returns bigint language sql as $$ select 1::bigint $$;
create function cron.unschedule(n text) returns boolean language sql as $$ select true $$;
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
alter default privileges in schema public grant execute on functions to anon, authenticated, service_role;
