-- Миграция: переносим название/фото/описание товара из кода index.html в Supabase,
-- чтобы новые товары можно было полностью добавлять/удалять через админку.
-- Выполнить один раз в Supabase → SQL Editor.

alter table products
  add column if not exists name text,
  add column if not exists subtitle text default '',
  add column if not exists has_size boolean not null default true,
  add column if not exists photos text[] not null default '{}',
  add column if not exists intro text default '',
  add column if not exists details text default '',
  add column if not exists material text default '',
  add column if not exists size_guide text default '',
  add column if not exists production_note text default '';

-- Бэкфилл текущих 4 товаров тем же контентом, что сейчас зашит в index.html —
-- после миграции внешний вид сайта не должен измениться.

update products set
  name = 'Цепь "Loa"',
  subtitle = 'Подвеска LOA — Chain',
  has_size = false,
  photos = array[
    'https://static.tildacdn.com/tild6165-3661-4435-b565-336238373737/photo.jpg',
    'https://thb.tildacdn.com/tild6165-3164-4366-b736-643835303761/-/resize/1200x/__.jpg'
  ],
  intro = $$Подвеска LOA — это финальный акцент дропа. Минимальный, но считываемый. Не про демонстрацию, а про принадлежность.
Буквы LOA выполнены в чёткой форме и зафиксированы на массивной цепи, создавая баланс между чистотой и весом. Подвеска ощущается как объект, а не украшение — она дополняет образ, не перетягивая внимание.
Работает как самостоятельный элемент и как продолжение философии дропа: тишина, утрата, контроль.$$,
  details = $$Материал: металл, покрытие устойчиво к потускнению
Подвеска: буквы LOA на цепи
Универсальная длина цепи$$,
  material = '',
  size_guide = '',
  production_note = $$Подвеска производится под заказ.
Срок отправки — до 14 дней с момента оформления.$$
where id = 1;

update products set
  name = 'Худи "Loa"',
  subtitle = 'Худи LOA — Wings (Black)',
  has_size = true,
  photos = array[
    'assets/design-hoodie.jpg',
    'https://static.tildacdn.com/tild6362-3038-4835-b031-313564643538/photo.jpg',
    'https://i.imgur.com/R00rZyU.jpg',
    'https://i.imgur.com/BeII4y1.jpg',
    'assets/gallery-group-front.jpg'
  ],
  intro = $$Худи Wings — центральный объект дропа. Про внутреннюю тяжесть и скрытую силу, про желание уйти и остаться одновременно.
Крылья на груди выполнены в мягком, матовом сером оттенке — без резких границ и лишней агрессии. Они не выглядят как декор, а как часть ткани и формы.$$,
  details = $$Цвет: чёрный
Принт спереди: логотип Lost of All
Принт сзади: крылья + логотип LOA
Крой: свободный оверсайз
Посадка: комфортная, унисекс$$,
  material = $$Плотный футер
Мягкий на ощупь, держит форму$$,
  size_guide = 'hoodie',
  production_note = $$Худи производится под заказ.
Срок отправки — до 14 дней после оформления.$$
where id = 2;

update products set
  name = 'Футболка "Loa" BLACK',
  subtitle = 'Футболка LOA — Lost of All (Black)',
  has_size = true,
  photos = array[
    'assets/design-black-tee.jpg',
    'https://static.tildacdn.com/tild3666-3432-4666-b035-373633363835/noroot.png',
    'https://i.imgur.com/SOhZvD0.jpeg',
    'https://i.imgur.com/wqEGG8Q.jpg',
    'assets/gallery-group-both.jpg'
  ],
  intro = $$Футболка Lost of All — это состояние, а не фраза. Про момент, когда всё лишнее исчезает, и остаёшься только ты и тишина.
Минималистичный фронтальный принт выполнен в мягком, почти незаметном тоне — он читается только вблизи. На спине — крылья LOA, как символ утраты и одновременно внутренней свободы.$$,
  details = $$Цвет: чёрный
Принт спереди: Lost of All / SS'24
Принт сзади: крылья + логотип LOA
Крой: свободный оверсайз$$,
  material = $$Плотный хлопок
Мягкий на ощупь, держит форму после стирки$$,
  size_guide = 'tee',
  production_note = $$Изделие производится под заказ.
Срок отправки — до 14 дней после оформления.$$
where id = 3;

update products set
  name = 'Футболка "Loa" WHITE',
  subtitle = 'Футболка LOA — Lost of All (White)',
  has_size = true,
  photos = array[
    'assets/design-white-tee.jpg',
    'assets/white-tee-front.jpg',
    'assets/white-tee-back.jpg',
    'assets/white-tee-lifestyle.jpg'
  ],
  intro = $$Та же философия — чистый тон. Свободный оверсайз-крой, плотный хлопок.
Минималистичный принт спереди и крылья на спине. Футболка становится продолжением вашего внутреннего состояния.$$,
  details = $$Цвет: белый
Принт спереди: Lost of All / SS'24
Принт сзади: крылья + логотип LOA (низкий контраст)
Крой: свободный оверсайз$$,
  material = $$Плотный хлопок
Мягкий на ощупь, долговечный$$,
  size_guide = 'tee',
  production_note = $$Изделие производится под заказ.
Срок отправки — до 14 дней после оформления.$$
where id = 4;

-- Начиная со следующего id (5, 6, ...) — товары, добавленные только через админку,
-- без строки кода в index.html.
