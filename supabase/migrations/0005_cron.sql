-- Annule chaque minute les demandes sans réponse et les rendez-vous non payés
-- à temps (règles de 0004).
create extension if not exists pg_cron with schema pg_catalog;

select cron.schedule(
  'expire-stale-bookings',
  '* * * * *',
  'select public.expire_stale_bookings()'
);
