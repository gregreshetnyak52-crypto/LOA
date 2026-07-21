-- Миграция: переносим заказы и авторизацию покупателей с Firebase на Supabase.
-- Выполнить один раз в Supabase → SQL Editor (после supabase_migration_products.sql).

-- ============================================================
-- ТАБЛИЦА АДМИНОВ — сам факт строки с этим user_id даёт права
-- ============================================================
create table if not exists admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);

insert into admins (user_id)
select id from auth.users where email = 'loacompany@yandex.com'
on conflict (user_id) do nothing;

alter table admins enable row level security;

-- Каждый может проверить только "я сам админ?", не может увидеть чужие/все записи —
-- этого достаточно для проверок exists(...) внутри политик orders ниже.
create policy admins_select_own on admins for select
  using (auth.uid() = user_id);

-- ============================================================
-- ТАБЛИЦА ЗАКАЗОВ
-- ============================================================
create table if not exists orders (
  id uuid primary key default gen_random_uuid(),
  uid uuid references auth.users(id) on delete set null,
  name text not null,
  phone text not null,
  tg text default '',
  items text not null,
  total text not null,
  pvz text default '',
  date text not null,
  status text not null default 'new',
  payment_status text not null default 'awaiting',
  payment_operation_id text,
  created_at timestamptz not null default now(),
  status_updated_at timestamptz
);

alter table orders enable row level security;

-- Создать заказ может гость (uid не указан) или залогиненный (только на свой uid).
-- Обязательно приходит в статусе "новый, оплата ожидается" — клиент не может сам
-- объявить заказ оплаченным при создании.
create policy orders_insert on orders for insert
  with check (
    status = 'new' and payment_status = 'awaiting'
    and (
      (auth.uid() is not null and uid = auth.uid())
      or (auth.uid() is null and uid is null)
    )
  );

-- Залогиненный видит только свои заказы (auth.uid() нельзя подделать — это из JWT,
-- а не из параметра запроса, поэтому безопасно разрешать даже список, не только один).
create policy orders_select_own on orders for select
  using (auth.uid() is not null and uid = auth.uid());

-- Админ видит и меняет всё, но менять можно только статус (оплату трогает только
-- сервер — Edge Function вебхука ЮMoney, который работает через service role и эти
-- правила не проверяет вовсе).
create policy orders_select_admin on orders for select
  using (exists (select 1 from admins where user_id = auth.uid()));

create policy orders_update_admin on orders for update
  using (exists (select 1 from admins where user_id = auth.uid()))
  with check (exists (select 1 from admins where user_id = auth.uid()));

-- ============================================================
-- ГОСТЕВАЯ ПРОВЕРКА СТАТУСА ОПЛАТЫ ПО ID
-- ============================================================
-- Гостю (без аккаунта) после оплаты нужно прочитать статус СВОЕГО заказа по ID из
-- redirect-ссылки. Обычный select с политикой "uid is null" был бы опасен — тогда
-- любой мог бы получить СПИСОК всех гостевых заказов разом. Эта функция принимает
-- только конкретный ID и возвращает только его — угадать/перечислить нельзя.
create or replace function get_guest_order_status(order_id uuid)
returns table (status text, payment_status text, total text, items text, date text, pvz text, name text)
language sql security definer
set search_path = public
as $$
  select status, payment_status, total, items, date, pvz, name
  from orders
  where id = order_id and uid is null;
$$;

grant execute on function get_guest_order_status(uuid) to anon, authenticated;
