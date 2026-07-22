-- Хардненинг после security-ревью (2026-07-22): закрывает пробелы, не покрытые
-- предыдущими миграциями. Выполнить в Supabase → SQL Editor.

-- ============================================================
-- RLS ДЛЯ products / sizes / settings — в репозитории до этого момента не было
-- ни одной строки, определяющей политики для этих таблиц (только ALTER/UPDATE
-- для данных). Публичное чтение нужно витрине, писать может только admins.
-- ============================================================
alter table products enable row level security;
alter table sizes enable row level security;
alter table settings enable row level security;

create policy products_select_all on products for select using (true);
create policy sizes_select_all on sizes for select using (true);
create policy settings_select_all on settings for select using (true);

create policy products_admin_write on products for all
  using (exists (select 1 from admins where user_id = auth.uid()))
  with check (exists (select 1 from admins where user_id = auth.uid()));

create policy sizes_admin_write on sizes for all
  using (exists (select 1 from admins where user_id = auth.uid()))
  with check (exists (select 1 from admins where user_id = auth.uid()));

create policy settings_admin_write on settings for all
  using (exists (select 1 from admins where user_id = auth.uid()))
  with check (exists (select 1 from admins where user_id = auth.uid()));

-- ============================================================
-- КОЛОНОЧНОЕ ОГРАНИЧЕНИЕ ДЛЯ orders — RLS-политика orders_update_admin разрешает
-- админу обновлять ЛЮБУЮ колонку, включая payment_status (что должен делать
-- только сервер вебхука через service_role). Ограничиваем на уровне грантов,
-- что вообще может менять роль authenticated — RLS сама по себе колонки не режет.
-- service_role (вебхук, create-payment) этими грантами не ограничен.
-- ============================================================
revoke update on orders from authenticated;
grant update (status, status_updated_at) on orders to authenticated;

-- ============================================================
-- Структурированный состав корзины — create-payment пересчитывает сумму к оплате
-- по этим id из products, а не доверяет total, который прислал браузер.
-- ============================================================
alter table orders add column if not exists items_json jsonb;

-- ============================================================
-- Разумные ограничения длины полей заказа — на случай прямых вызовов REST API
-- мимо сайта и Edge Functions (например, скриптом с публичным ключом).
-- ============================================================
alter table orders add constraint orders_name_len check (char_length(name) <= 100);
alter table orders add constraint orders_phone_len check (char_length(phone) <= 30);
alter table orders add constraint orders_tg_len check (char_length(tg) <= 50);
alter table orders add constraint orders_pvz_len check (char_length(pvz) <= 500);
alter table orders add constraint orders_items_len check (char_length(items) <= 2000);
