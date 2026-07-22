// Создаёт платёж в ЮKassa для уже существующего заказа и возвращает ссылку на оплату
// (confirmation_url), куда браузер перенаправляет покупателя.
//
// ВАЖНО: сумма пересчитывается здесь из актуальных цен в таблице products по
// order.items_json — заказ.total, который прислал браузер, для суммы к оплате не
// используется вовсе (только для отображения в админке/Telegram). Иначе кто угодно
// мог бы подделать цену в devtools. Секретный ключ ЮKassa виден только серверу (эта
// функция), в браузер он никогда не попадает.
//
// Деплой (из папки Сайты/loashop):
//   supabase functions deploy create-payment --no-verify-jwt
//
// Секреты (Shop ID не секретный, но проще хранить вместе с ключом):
//   supabase secrets set YOOKASSA_SHOP_ID=твой_shop_id
//   supabase secrets set YOOKASSA_SECRET_KEY=твой_секретный_ключ

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const SHOP_ID = Deno.env.get('YOOKASSA_SHOP_ID');
const SECRET_KEY = Deno.env.get('YOOKASSA_SECRET_KEY');
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const SITE_URL = Deno.env.get('SITE_URL') || 'https://loashop.ru';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const ykAuth = () => btoa(`${SHOP_ID}:${SECRET_KEY}`);

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }
  if (req.method !== 'POST') {
    return new Response('Method Not Allowed', { status: 405, headers: corsHeaders });
  }
  if (!SHOP_ID || !SECRET_KEY) {
    console.error('YOOKASSA_SHOP_ID / YOOKASSA_SECRET_KEY не настроены (supabase secrets set ...)');
    return new Response(JSON.stringify({ error: 'Server misconfigured' }), { status: 500, headers: corsHeaders });
  }

  let orderId: string | undefined;
  try {
    const body = await req.json();
    orderId = body.order_id;
  } catch {
    return new Response(JSON.stringify({ error: 'Invalid JSON' }), { status: 400, headers: corsHeaders });
  }
  if (!orderId) {
    return new Response(JSON.stringify({ error: 'Missing order_id' }), { status: 400, headers: corsHeaders });
  }

  const supabase = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);
  const { data: order, error: fetchErr } = await supabase
    .from('orders')
    .select('*')
    .eq('id', orderId)
    .maybeSingle();

  if (fetchErr || !order) {
    return new Response(JSON.stringify({ error: 'Order not found' }), { status: 404, headers: corsHeaders });
  }

  // Гостевой заказ (uid IS NULL) оплатить может любой, у кого есть его id — так и
  // задумано (см. get_guest_order_status). Но если заказ привязан к аккаунту, платить
  // за него должен именно этот аккаунт, а не первый, кто узнал/подобрал order_id.
  if (order.uid) {
    const authHeader = req.headers.get('Authorization') || '';
    const token = authHeader.replace(/^Bearer\s+/i, '');
    const { data: { user }, error: authErr } = token ? await supabase.auth.getUser(token) : { data: { user: null }, error: null };
    if (authErr || !user || user.id !== order.uid) {
      return new Response(JSON.stringify({ error: 'Not your order' }), { status: 403, headers: corsHeaders });
    }
  }

  if (order.status !== 'new' || order.payment_status !== 'awaiting') {
    return new Response(JSON.stringify({ error: 'Order is not payable' }), { status: 400, headers: corsHeaders });
  }

  // Идемпотентность: если платёж для этого заказа уже был создан (двойной клик,
  // повторный вызов) и всё ещё ожидает оплаты — отдаём ту же ссылку вместо того,
  // чтобы плодить новые платежи в ЮKassa на один и тот же заказ.
  if (order.payment_operation_id) {
    const existing = await fetch(`https://api.yookassa.ru/v3/payments/${order.payment_operation_id}`, {
      headers: { Authorization: `Basic ${ykAuth()}` },
    });
    if (existing.ok) {
      const existingPayment = await existing.json();
      if (existingPayment.status === 'pending' || existingPayment.status === 'waiting_for_capture') {
        return new Response(
          JSON.stringify({ confirmation_url: existingPayment.confirmation?.confirmation_url }),
          { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
        );
      }
    }
  }

  // Сумма — только из актуальных цен в products по items_json, а не из order.total
  // (тот пишет браузер и ему верить нельзя). Скидка берётся из settings так же, как
  // её видит покупатель на витрине.
  const items: Array<{ id: number }> = Array.isArray(order.items_json) ? order.items_json : [];
  let amountValue: string;

  if (items.length) {
    const ids = [...new Set(items.map((i) => i.id))];
    const [{ data: products }, { data: settings }] = await Promise.all([
      supabase.from('products').select('id, price_rub').in('id', ids),
      supabase.from('settings').select('global_discount').eq('id', 1).maybeSingle(),
    ]);
    const discount = settings?.global_discount || 0;
    const priceById = new Map((products || []).map((p: any) => [p.id, p.price_rub]));

    let total = 0;
    for (const item of items) {
      const price = priceById.get(item.id);
      if (typeof price !== 'number') {
        return new Response(JSON.stringify({ error: 'Unknown product in order' }), { status: 400, headers: corsHeaders });
      }
      total += discount ? Math.round(price - (price * discount) / 100) : price;
    }
    amountValue = total.toFixed(2);
  } else {
    // Заказы без items_json (оформлены до этого изменения) — структурных данных для
    // пересчёта нет, используем то, что уже записано.
    amountValue = parseFloat(String(order.total).replace(/[^\d.]/g, '')).toFixed(2);
  }

  const shortId = orderId.slice(-6).toUpperCase();

  const ykResponse = await fetch('https://api.yookassa.ru/v3/payments', {
    method: 'POST',
    headers: {
      Authorization: `Basic ${ykAuth()}`,
      'Idempotence-Key': orderId,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      amount: { value: amountValue, currency: 'RUB' },
      capture: true,
      confirmation: {
        type: 'redirect',
        return_url: `${SITE_URL}/index.html?paid=true&order=${orderId}`,
      },
      description: `Заказ LOA №${shortId}`,
      metadata: { order_id: orderId },
    }),
  });

  if (!ykResponse.ok) {
    const errText = await ykResponse.text();
    console.error('Ошибка создания платежа ЮKassa', { status: ykResponse.status, errText });
    return new Response(JSON.stringify({ error: 'Payment creation failed' }), { status: 502, headers: corsHeaders });
  }

  const payment = await ykResponse.json();

  const { error: updateErr } = await supabase.from('orders').update({ payment_operation_id: payment.id }).eq('id', orderId);
  if (updateErr) {
    console.error('Не удалось сохранить payment_operation_id', { orderId, updateErr });
  }

  return new Response(
    JSON.stringify({ confirmation_url: payment.confirmation?.confirmation_url }),
    { status: 200, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
  );
});
