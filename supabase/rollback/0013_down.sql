-- Retour arrière de 0013_admin_console.sql (avant 0012_down.sql).
-- Données perdues : montants des remboursements accordés par l'équipe
-- (bookings.admin_refunded). Les mouvements de solde correspondants restent
-- dans wallet_transactions ; le journal d'audit est conservé.

-- Garde-fou : ne s'exécute que si on le confirme explicitement dans la session :
--   set mynurse.confirm_rollback = 'yes';
do $$
begin
  if current_setting('mynurse.confirm_rollback', true) is distinct from 'yes' then
    raise exception 'Retour arrière non confirmé (set mynurse.confirm_rollback = yes).';
  end if;
end $$;

drop function if exists public.admin_dashboard_context(), public.admin_cancel_booking(uuid, text),
  public.admin_refund_booking(uuid, int, text), public.admin_extend_premium(uuid, int, text),
  public.admin_broadcast(text, text, text), public.admin_update_incident(uuid, text, text);
alter table public.bookings drop column if exists admin_refunded;

-- Recherche : version de 0012.
create or replace function public.search_pros(p_service text, p_commune text)
returns table (id uuid, display_name text, pro_type public.pro_type, price int,
               rating_avg numeric, rating_count int, care_count int, featured boolean)
language sql stable security invoker set search_path = '' as $$
  select p.id, p.display_name, p.pro_type, ps.price, p.rating_avg, p.rating_count, p.care_count,
         coalesce(p.premium_until > now(), false) as featured
  from public.pros p
  join public.pro_services ps on ps.pro_id = p.id and ps.service_id = p_service
  where p.verification_status = 'verified' and p_commune = any (p.communes)
    and private.pro_docs_ok(p.id)
  order by featured desc, p.rating_avg desc;
$$;
