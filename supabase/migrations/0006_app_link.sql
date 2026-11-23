-- Branchement de l'app : position GPS du soin, et fiche du patient visible
-- par le soignant dès la demande (nom, allergies), pas seulement après
-- acceptation.

alter table public.bookings
  add column location_lat double precision check (location_lat between -90 and 90),
  add column location_lng double precision check (location_lng between -180 and 180);
grant insert (location_lat, location_lng) on public.bookings to authenticated;

create or replace function private.treats_patient(p_patient uuid) returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (
    select 1 from public.bookings
    where patient_id = p_patient and pro_id = (select auth.uid())
      and status in ('pending', 'accepted', 'done')
  );
$$;
