-- Porte-monnaie MyNurse : solde des patients (recharges, paiements,
-- remboursements) et des soignants (gains, retraits).
-- Chaque mouvement passe par private.wallet_move, dans la même transaction
-- que l'action qui le provoque. Aucun solde ne peut devenir négatif.

create type public.wallet_tx_kind as enum ('topup', 'payment', 'refund', 'earning', 'withdrawal');

create table public.wallets (
  owner_id uuid primary key references public.profiles on delete cascade,
  balance int not null default 0 check (balance >= 0),
  updated_at timestamptz not null default now()
);

create table public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles on delete cascade,
  kind public.wallet_tx_kind not null,
  amount int not null check (amount <> 0),
  booking_id uuid references public.bookings,
  external_ref text,
  label text not null default '',
  created_at timestamptz not null default now()
);
create index wallet_transactions_owner_idx on public.wallet_transactions (owner_id, created_at desc);
-- Une recharge ou un remboursement ne peut être crédité qu'une fois.
create unique index wallet_transactions_ref_idx on public.wallet_transactions (kind, external_ref)
  where external_ref is not null;
create unique index wallet_transactions_booking_idx on public.wallet_transactions (kind, booking_id)
  where booking_id is not null;

-- Demandes de retrait, exécutées par le serveur via l'API de l'agrégateur.
create table public.withdrawals (
  id uuid primary key default gen_random_uuid(),
  pro_id uuid not null references public.pros on delete cascade,
  amount int not null check (amount >= 1000),
  method text not null check (method in ('orange', 'mtn', 'moov', 'wave')),
  phone text not null check (phone ~ '^[0-9]{10}$'),
  status text not null default 'pending' check (status in ('pending', 'sent', 'failed')),
  external_ref text,
  created_at timestamptz not null default now()
);
create index withdrawals_pro_idx on public.withdrawals (pro_id, created_at desc);

alter table public.bookings drop constraint bookings_payment_method_check;
alter table public.bookings add constraint bookings_payment_method_check
  check (payment_method in ('wallet', 'orange', 'mtn', 'moov', 'wave'));

-- Mouvement de solde : crée le porte-monnaie au besoin, refuse un solde négatif.
create function private.wallet_move(
  p_owner uuid, p_kind public.wallet_tx_kind, p_amount int,
  p_booking uuid default null, p_ref text default null, p_label text default ''
) returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_balance int;
begin
  insert into public.wallets (owner_id) values (p_owner) on conflict do nothing;
  update public.wallets set balance = balance + p_amount, updated_at = now()
    where owner_id = p_owner and balance + p_amount >= 0
    returning balance into v_balance;
  if v_balance is null then
    raise exception 'Solde insuffisant.';
  end if;
  insert into public.wallet_transactions (owner_id, kind, amount, booking_id, external_ref, label)
    values (p_owner, p_kind, p_amount, p_booking, p_ref, p_label);
  return v_balance;
end;
$$;

-- Recharge : appelée uniquement par le webhook de l'agrégateur (clé serveur).
create function public.confirm_topup(p_owner uuid, p_amount int, p_method text, p_ref text) returns int
language plpgsql security definer set search_path = '' as $$
begin
  if p_amount < 500 or p_amount > 500000 then
    raise exception 'Montant hors limites.';
  end if;
  if coalesce(p_ref, '') = '' then
    raise exception 'Référence de paiement manquante.';
  end if;
  return private.wallet_move(p_owner, 'topup', p_amount, null, p_ref,
    'Recharge ' || p_method);
end;
$$;

-- Le patient paie un soin confirmé avec son solde.
create function public.pay_booking_with_wallet(p_booking uuid) returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_price int;
  v_balance int;
begin
  select price into v_price from public.bookings
    where id = p_booking and booked_by = (select auth.uid())
      and status = 'accepted' and paid_at is null
    for update;
  if v_price is null then
    raise exception 'Ce soin n''est pas à payer.';
  end if;
  v_balance := private.wallet_move((select auth.uid()), 'payment', -v_price, p_booking, null, 'Paiement d''un soin');
  update public.bookings set paid_at = now(), payment_method = 'wallet' where id = p_booking;
  return v_balance;
end;
$$;

-- Le soignant demande un retrait de ses gains.
create function public.request_withdrawal(p_amount int, p_method text, p_phone text) returns int
language plpgsql security definer set search_path = '' as $$
declare
  v_balance int;
begin
  if not exists (select 1 from public.pros where id = (select auth.uid())) then
    raise exception 'Réservé aux soignants.';
  end if;
  if p_amount < 1000 then
    raise exception 'Montant minimum : 1 000 FCFA.';
  end if;
  v_balance := private.wallet_move((select auth.uid()), 'withdrawal', -p_amount, null, null, 'Retrait ' || p_method);
  insert into public.withdrawals (pro_id, amount, method, phone)
    values ((select auth.uid()), p_amount, p_method, p_phone);
  return v_balance;
end;
$$;

-- Rembourse un soin payé sur le solde du patient.
create function private.refund_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = '' as $$
declare
  b record;
begin
  select booked_by, price, paid_at into b from public.bookings where id = p_booking;
  if b.paid_at is not null then
    perform private.wallet_move(b.booked_by, 'refund', b.price, p_booking, null, 'Remboursement d''un soin');
  end if;
end;
$$;

-- Création du porte-monnaie à l'inscription.
create or replace function private.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, role, full_name, phone)
  values (
    new.id,
    case when new.raw_user_meta_data ->> 'role' = 'pro' then 'pro'::public.user_role else 'patient'::public.user_role end,
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    new.phone
  );
  insert into public.wallets (owner_id) values (new.id);
  return new;
end;
$$;

-- Fin du soin : le soignant est crédité, commission déduite.
create or replace function private.on_care_log() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_earning int;
begin
  update public.bookings set status = 'done'
    where id = new.booking_id and pro_id = new.pro_id and status = 'accepted'
      and paid_at is not null
    returning price - commission into v_earning;
  if v_earning is null then
    raise exception 'Ce soin n''est pas confirmé, pas payé ou ne vous est pas attribué.';
  end if;
  update public.pros set care_count = care_count + 1 where id = new.pro_id;
  perform private.wallet_move(new.pro_id, 'earning', v_earning, new.booking_id, null, 'Soin terminé');
  return new;
end;
$$;

create or replace function public.cancel_booking(p_booking uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  update public.bookings
    set status = 'cancelled', refunded = paid_at is not null,
        cancel_reason = 'Annulé par le patient'
    where id = p_booking and booked_by = (select auth.uid()) and status in ('pending', 'accepted');
  if not found then
    raise exception 'Ce soin ne peut plus être annulé.';
  end if;
  perform private.refund_booking(p_booking);
end;
$$;

create or replace function public.admin_suspend_pro(p_pro uuid, p_reason text) returns void
language plpgsql security definer set search_path = '' as $$
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
      set status = 'cancelled', refunded = paid_at is not null,
          cancel_reason = 'Soignant suspendu par MyNurse'
      where pro_id = p_pro and status in ('pending', 'accepted')
      returning id
  loop
    perform private.refund_booking(v_id);
  end loop;
end;
$$;

-- Droits : lecture de ses propres soldes ; aucune écriture directe.
alter table public.wallets enable row level security;
alter table public.wallet_transactions enable row level security;
alter table public.withdrawals enable row level security;
revoke all on public.wallets, public.wallet_transactions, public.withdrawals from anon, authenticated;
grant select on public.wallets, public.wallet_transactions, public.withdrawals to authenticated;

create policy wallets_select on public.wallets for select to authenticated
  using (owner_id = (select auth.uid()) or (select private.is_admin()));
create policy wallet_transactions_select on public.wallet_transactions for select to authenticated
  using (owner_id = (select auth.uid()) or (select private.is_admin()));
create policy withdrawals_select on public.withdrawals for select to authenticated
  using (pro_id = (select auth.uid()) or (select private.is_admin()));

revoke execute on function public.confirm_topup(uuid, int, text, text) from public, anon, authenticated;
revoke execute on function public.pay_booking_with_wallet(uuid) from public, anon;
revoke execute on function public.request_withdrawal(int, text, text) from public, anon;
grant execute on function public.pay_booking_with_wallet(uuid) to authenticated;
grant execute on function public.request_withdrawal(int, text, text) to authenticated;
