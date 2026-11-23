-- Commission MyNurse : 10 % sur tous les soins (décision de Jared, 23/11/2026).
-- Avant : 15 % par soin ponctuel, 10 % sur un suivi régulier.
-- Les soins déjà créés gardent le taux enregistré à leur création
-- (colonne commission_rate) : seuls les nouveaux soins passent à 10 %.

alter table public.bookings alter column commission_rate set default 0.10;

-- Même fonction que dans 0004_business_rules.sql, avec le taux unique.
create or replace function private.price_booking() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_price int;
  v_hour int;
  v_night_ok boolean;
  v_needs_rx boolean;
  v_duration int;
  v_first public.bookings;
begin
  select ps.price, p.night_available, s.needs_prescription, s.duration_minutes
    into v_price, v_night_ok, v_needs_rx, v_duration
  from public.pro_services ps
  join public.pros p on p.id = ps.pro_id
  join public.services s on s.id = ps.service_id
  where ps.pro_id = new.pro_id and ps.service_id = new.service_id
    and p.verification_status = 'verified' and s.active
    and new.commune = any (p.communes);
  if v_price is null then
    raise exception 'Ce soignant ne propose pas ce soin dans cette commune.';
  end if;
  if new.scheduled_at < now() + interval '1 hour' then
    raise exception 'Réservez au moins 1 h à l''avance, le temps que le soignant se déplace.';
  end if;
  if new.scheduled_at > now() + interval '60 days' then
    raise exception 'On ne réserve pas plus de 60 jours à l''avance.';
  end if;
  if v_needs_rx and not new.has_prescription then
    raise exception 'Ce soin se fait uniquement sur ordonnance.';
  end if;
  v_hour := extract(hour from new.scheduled_at at time zone 'Africa/Abidjan');
  new.night := v_hour >= 21 or v_hour < 6;
  if new.night and not v_night_ok then
    raise exception 'Ce soignant ne fait pas de soins de nuit.';
  end if;
  new.slot := tstzrange(new.scheduled_at, new.scheduled_at + make_interval(mins => v_duration));
  if exists (
    select 1 from public.bookings b
    where b.pro_id = new.pro_id and b.status = 'accepted' and b.slot && new.slot
  ) then
    raise exception 'Ce soignant a déjà un soin à cette heure. Choisissez un autre créneau.';
  end if;
  -- Suivi régulier : même patient, même soignant, même soin.
  if new.contract_id is not null then
    if not exists (select 1 from public.contracts c
                   where c.id = new.contract_id and c.booked_by = new.booked_by) then
      raise exception 'Suivi introuvable.';
    end if;
    select * into v_first from public.bookings
      where contract_id = new.contract_id order by session_index limit 1;
    if found and (v_first.pro_id, v_first.service_id, v_first.patient_id)
                 is distinct from (new.pro_id, new.service_id, new.patient_id) then
      raise exception 'Toutes les séances d''un suivi concernent le même soin et le même soignant.';
    end if;
    if (select count(*) from public.bookings where contract_id = new.contract_id) >= 30 then
      raise exception 'Un suivi compte au plus 30 séances.';
    end if;
  end if;
  -- Commission unique de 10 %, soin ponctuel comme suivi régulier.
  new.commission_rate := 0.10;
  new.base_price := v_price;
  new.price := case when new.night then round(v_price * 1.5) else v_price end;
  new.commission := round(new.price * new.commission_rate);
  new.status := 'pending';
  new.created_at := now();
  return new;
end;
$$;

