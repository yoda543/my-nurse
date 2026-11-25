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
