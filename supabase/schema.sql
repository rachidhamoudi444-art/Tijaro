-- =====================================================================
-- Delivery platform (Tipaza) - MVP schema for Supabase / PostgreSQL
-- Principles:
--   * Money never changes from the apps directly: only via SECURITY DEFINER functions.
--   * wallet_ledger / store_ledger are append-only (no update/delete, enforced by trigger).
--   * Every user reads only their own data (Row Level Security).
-- =====================================================================

create extension if not exists pgcrypto;

-- ---------- Types ----------
create type user_role     as enum ('customer','store','courier','admin');
create type account_state as enum ('active','banned','suspended');
create type order_type    as enum ('store','p2p','free');           -- متجر / نقطة لنقطة / طلب حر
create type order_status  as enum ('new','accepted','preparing','ready','picked_up','on_the_way',
                                   'delivered','not_delivered','dispute','rejected','cancelled');
create type fault_party   as enum ('customer','courier','store');
create type ledger_kind   as enum ('topup','commission','compensation','adjustment');
create type store_ledger_kind as enum ('sale','store_commission','compensation_charge','payout','adjustment');
create type topup_state   as enum ('pending','confirmed','rejected');

-- ---------- Settings (editable only by admin) ----------
create table app_settings (
  key   text primary key,
  value numeric not null,
  note  text
);
insert into app_settings(key, value, note) values
  ('courier_commission_rate',   0.10, 'عمولة التوصيل من الليفرور (أول 3 أشهر 10%)'),
  ('store_commission_rate',     0.00, 'عمولة المتجر (0% في البداية)'),
  ('min_wallet_balance',        1000, 'الحد الأدنى لرصيد الليفرور لاستقبال الطلبات (دج)'),
  ('customer_fault_ban_after',  2,    'عدد أخطاء الزبون قبل الحظر'),
  ('compensation_rate',         0.5,  'تعويض الليفرور = نسبة من سعر التوصيل'),
  ('compensation_weekly_cap',   1500, 'سقف تعويضات الليفرور الأسبوعي (دج)'),
  ('wait_minutes_at_address',   10,   'مدة الانتظار عند العنوان قبل خطأ الزبون'),
  ('required_call_attempts',    3,    'عدد محاولات الاتصال المسجلة المطلوبة'),
  ('free_order_service_fee',    100,  'مبلغ خدمة ثابت للطلب الحر (شراء وتوصيل) (دج)'),
  ('free_order_max_purchase',   2000, 'سقف مبلغ الشراء في الطلب الحر (دج)'),
  ('cash_open_alert',           10000,'تنبيه الأدمن عند تجاوز نقد الليفرور المفتوح (دج)'),
  ('deposit_required',          0,    '1 = تفعيل الضمان وسقف النقد (مغلق في التجربة)'),
  ('dispatch_nearest_count',    3,    'عدد أقرب الليفرورات الذين يرون الطلب أولاً'),
  ('dispatch_exclusive_seconds',45,    'بعد هذه المدة (ثوانٍ) يراه كل الليفرورات المتاحين');

-- ---------- الولايات والبلديات (مجهّزة مسبقاً، وكلها محجوبة إلا ما يفتحه الأدمن) ----------
create table wilayas (
  id      int primary key,          -- رمز الولاية الرسمي
  name_ar text not null,
  name_fr text not null
);
create table communes (
  id        int primary key,        -- رمز البلدية (رمز الولاية * 100 + رقم)
  wilaya_id int not null references wilayas(id),
  name_ar   text not null,
  name_fr   text not null,
  is_active boolean not null default false   -- false = محجوبة (قريباً)
);
create index on communes(wilaya_id);
insert into wilayas(id,name_ar,name_fr) values
  (9,'البليدة','Blida'),
  (16,'الجزائر','Alger'),
  (19,'سطيف','Sétif'),
  (23,'عنابة','Annaba'),
  (25,'قسنطينة','Constantine'),
  (31,'وهران','Oran'),
  (42,'تيبازة','Tipaza');
insert into communes(id,wilaya_id,name_ar,name_fr) values
  (901,9,'البليدة','Blida'),
  (902,9,'الشبلي','Chebli'),
  (903,9,'بوعينان','Bouinan'),
  (904,9,'وادي العلايق','Oued El Alleug'),
  (905,9,'أولاد يعيش','Ouled Yaich'),
  (906,9,'الشريعة','Chrea'),
  (907,9,'العفرون','El-affroun'),
  (908,9,'الشفة','Chiffa'),
  (909,9,'حمام ملوان','Hammam Melouane'),
  (910,9,'بن خليل','Benkhelil'),
  (911,9,'الصومعة','Souma'),
  (912,9,'موزاية','Mouzaia'),
  (913,9,'سوحان','Souhane'),
  (914,9,'مفتاح','Meftah'),
  (915,9,'أولاد سلامة','Ouled Slama'),
  (916,9,'بوفاريك','Boufarik'),
  (917,9,'الأربعاء','Larbaa'),
  (918,9,'وادي جر','Oued Djer'),
  (919,9,'بني تامو','Beni-tamou'),
  (920,9,'بوعرفة','Bouarfa'),
  (921,9,'بني مراد','Beni Mered'),
  (922,9,'بوقرة','Bougara'),
  (923,9,'قرواو','Guerrouaou'),
  (924,9,'عين الرمانة','Ain Romana'),
  (925,9,'جبابرة','Djebabra'),
  (1601,16,'الجزائر','Alger Centre'),
  (1602,16,'سيدي امحمد','Sidi M''hamed'),
  (1603,16,'المدنية','El Madania'),
  (1604,16,'محمد بلوزداد','Mohamed Belouzdad'),
  (1605,16,'باب الوادي','Bab El Oued'),
  (1606,16,'بولوغين بن زيري','Bologhine Ibnou Ziri'),
  (1607,16,'القصبة','Casbah'),
  (1608,16,'وادي قريش','Oued Koriche'),
  (1609,16,'بئر مراد رايس','Bir Mourad Rais'),
  (1610,16,'الابيار','El Biar'),
  (1611,16,'بوزريعة','Bouzareah'),
  (1612,16,'بئر خادم','Birkhadem'),
  (1613,16,'الحراش','El Harrach'),
  (1614,16,'براقي','Baraki'),
  (1615,16,'وادي السمار','Oued Smar'),
  (1616,16,'بوروبة','Bourouba'),
  (1617,16,'حسين داي','Hussein Dey'),
  (1618,16,'القبة','Kouba'),
  (1619,16,'باش جراح','Bachedjerah'),
  (1620,16,'الدار البيضاء','Dar El Beida'),
  (1621,16,'باب الزوار','Bab Ezzouar'),
  (1622,16,'ابن عكنون','Ben Aknoun'),
  (1623,16,'دالي ابراهيم','Dely Ibrahim'),
  (1624,16,'الحمامات الرومانية','Bains Romains'),
  (1625,16,'الرايس حميدو','Rais Hamidou'),
  (1626,16,'جسر قسنطينة','Djasr Kasentina'),
  (1627,16,'المرادية','El Mouradia'),
  (1628,16,'حيدرة','Hydra'),
  (1629,16,'المحمدية','Mohammadia'),
  (1630,16,'برج الكيفان','Bordj El Kiffan'),
  (1631,16,'المغارية','El Magharia'),
  (1632,16,'بني مسوس','Beni Messous'),
  (1633,16,'الكاليتوس','Les Eucalyptus'),
  (1634,16,'تسالة المرجة','Tessala El Merdja'),
  (1635,16,'أولاد شبل','Ouled Chebel'),
  (1636,16,'بئر توتة','Bir Touta'),
  (1637,16,'سيدي موسى','Sidi Moussa'),
  (1638,16,'الرويبة','Rouiba'),
  (1639,16,'هراوة','Herraoua'),
  (1640,16,'رغاية','Reghaia'),
  (1641,16,'عين طاية','Ain Taya'),
  (1642,16,'برج البحري','Bordj El Bahri'),
  (1643,16,'المرسى','El Merssa'),
  (1644,16,'زرالدة','Zeralda'),
  (1645,16,'السحاولة','Sehaoula'),
  (1646,16,'المعالمة','Maalma'),
  (1647,16,'بابا حسن','Baba Hesen'),
  (1648,16,'الدويرة','Douira'),
  (1649,16,'الدرارية','Draria'),
  (1650,16,'الرحمانية','Rahmania'),
  (1651,16,'أولاد فايت','Ouled Fayet'),
  (1652,16,'الشراقة','Cheraga'),
  (1653,16,'سطاوالي','Setaouali'),
  (1654,16,'العاشور','El Achour'),
  (1655,16,'سويدانية','Souidania'),
  (1656,16,'الخرايسية','Kheraisia'),
  (1657,16,'عين بنيان','Ain Benian'),
  (1901,19,'سطيف','Setif'),
  (1902,19,'العين الكبيرة','Ain El Kebira'),
  (1903,19,'بني عزيز','Beni-aziz'),
  (1904,19,'أولاد سي أحمد','Ouled Si Ahmed'),
  (1905,19,'بوطالب','Boutaleb'),
  (1906,19,'عين الروى','Ain-roua'),
  (1907,19,'ذراع القبيلة','Draa-kebila'),
  (1908,19,'بئر العرش','Bir-el-arch'),
  (1909,19,'بني شبانة','Beni Chebana'),
  (1910,19,'أولاد تبان','Ouled Tebben'),
  (1911,19,'الحامة','Hamma'),
  (1912,19,'معاوية','Maaouia'),
  (1913,19,'عين لقراج','Ain-legradj'),
  (1914,19,'عين عباسة','Ain Abessa'),
  (1915,19,'الدهامشة','Dehamcha'),
  (1916,19,'بابور','Babor'),
  (1917,19,'قجال','Guidjel'),
  (1918,19,'عين الحجر','Ain Lahdjar'),
  (1919,19,'بوسلام','Bousselam'),
  (1920,19,'العلمة','El Eulma'),
  (1921,19,'جميلة','Djemila'),
  (1922,19,'بني ورتيلان','Beni-ouartilane'),
  (1923,19,'الرصفة','Rosfa'),
  (1924,19,'أولاد عدوان','Ouled Addouane'),
  (1925,19,'بلعة','Bellaa'),
  (1926,19,'عين أرنات','Ain Arnat'),
  (1927,19,'عموشة','Amoucha'),
  (1928,19,'عين ولمان','Ain Oulmane'),
  (1929,19,'بيضاء برج','Beidha Bordj'),
  (1930,19,'بوعنداس','Bouandas'),
  (1931,19,'بازر الصخرة','Bazer-sakra'),
  (1932,19,'حمام السخنة','Hamam Soukhna'),
  (1933,19,'مزلوق','Mezloug'),
  (1934,19,'بئر حدادة','Bir Haddada'),
  (1935,19,'سرج الغول','Serdj-el-ghoul'),
  (1936,19,'حربيل','Harbil'),
  (1937,19,'الوريسية','El Ouricia'),
  (1938,19,'تيزي نبشار','Tizi N''bechar'),
  (1939,19,'صالح باي','Salah Bey'),
  (1940,19,'عين أزال','Ain Azel'),
  (1941,19,'قنزات','Guenzet'),
  (1942,19,'تالة إيفاسن','Tala-ifacene'),
  (1943,19,'بوقاعة','Bougaa'),
  (1944,19,'بني فودة','Beni Fouda'),
  (1945,19,'تاشودة','Tachouda'),
  (1946,19,'بني موحلي','Beni-mouhli'),
  (1947,19,'أولاد صابر','Ouled Sabor'),
  (1948,19,'قلال بوطالب','Guellal'),
  (1949,19,'عين السبت','Ain-sebt'),
  (1950,19,'حمام قرقور','Hammam Guergour'),
  (1951,19,'أيت نوال مزادة','Ait Naoual Mezada'),
  (1952,19,'قصر الأبطال','Ksar El Abtal'),
  (1953,19,'بني وسين','Beni Oussine'),
  (1954,19,'أيت تيزي','Ait-tizi'),
  (1955,19,'ماوكلان','Maouaklane'),
  (1956,19,'القتلة الزرقاء','Guelta Zerka'),
  (1957,19,'وادي البارد','Oued El Barad'),
  (1958,19,'الطاية','Taya'),
  (1959,19,'الولجة','El-ouldja'),
  (1960,19,'التلعة','Tella'),
  (2301,23,'عنابة','Annaba'),
  (2302,23,'برحال','Berrahel'),
  (2303,23,'الحجار','El Hadjar'),
  (2304,23,'العلمة','Eulma'),
  (2305,23,'البوني','El Bouni'),
  (2306,23,'وادي العنب','Oued El Aneb'),
  (2307,23,'الشرفاء','Cheurfa'),
  (2308,23,'سرايدي','Seraidi'),
  (2309,23,'عين الباردة','Ain Berda'),
  (2310,23,'شطايبي','Chetaibi'),
  (2311,23,'سيدي عامر','Sidi Amar'),
  (2312,23,'التريعات','Treat'),
  (2501,25,'قسنطينة','Constantine'),
  (2502,25,'حامة بوزيان','Hamma Bouziane'),
  (2503,25,'ابن باديس الهرية','Ben Badis'),
  (2504,25,'زيغود يوسف','Zighoud Youcef'),
  (2505,25,'ديدوش مراد','Didouche Mourad'),
  (2506,25,'الخروب','El Khroub'),
  (2507,25,'عين عبيد','Ain Abid'),
  (2508,25,'بني حميدان','Beni Hamidene'),
  (2509,25,'أولاد رحمون','Ouled Rahmouni'),
  (2510,25,'عين السمارة','Ain Smara'),
  (2511,25,'بوجريو مسعود','Messaoud Boujeriou'),
  (2512,25,'ابن زياد','Ibn Ziad'),
  (3101,31,'وهران','Oran'),
  (3102,31,'قديل','Gdyel'),
  (3103,31,'بئر الجير','Bir El Djir'),
  (3104,31,'حاسي بونيف','Hassi Bounif'),
  (3105,31,'السانية','Es Senia'),
  (3106,31,'أرزيو','Arzew'),
  (3107,31,'بطيوة','Bethioua'),
  (3108,31,'مرسى الحجاج','Marsat El Hadjadj'),
  (3109,31,'عين الترك','Ain Turk'),
  (3110,31,'العنصر','El Ancar'),
  (3111,31,'وادي تليلات','Oued Tlelat'),
  (3112,31,'طفراوي','Tafraoui'),
  (3113,31,'سيدي الشحمي','Sidi Chami'),
  (3114,31,'بوفتيس','Boufatis'),
  (3115,31,'المرسى الكبير','Mers El Kebir'),
  (3116,31,'بوصفر','Bousfer'),
  (3117,31,'الكرمة','El Kerma'),
  (3118,31,'البراية','El Braya'),
  (3119,31,'حاسي بن عقبة','Hassi Ben Okba'),
  (3120,31,'بن فريحة','Ben Freha'),
  (3121,31,'حاسي مفسوخ','Hassi Mefsoukh'),
  (3122,31,'سيدي بن يبقى','Sidi Ben Yebka'),
  (3123,31,'مسرغين','Messerghin'),
  (3124,31,'بوتليليس','Boutlelis'),
  (3125,31,'عين الكرمة','Ain Kerma'),
  (3126,31,'عين البية','Ain Biya'),
  (4201,42,'تيبازة','Tipaza'),
  (4202,42,'مناصر','Menaceur'),
  (4203,42,'الأرهاط','Larhat'),
  (4204,42,'دواودة','Douaouda'),
  (4205,42,'بورقيقة','Bourkika'),
  (4206,42,'خميستي','Khemisti'),
  (4207,42,'أغبال','Aghbal'),
  (4208,42,'حجوط','Hadjout'),
  (4209,42,'سيدي عامر','Sidi-amar'),
  (4210,42,'قوراية','Gouraya'),
  (4211,42,'الناظور','Nador'),
  (4212,42,'الشعيبة','Chaiba'),
  (4213,42,'عين تاقورايت','Ain Tagourait'),
  (4214,42,'شرشال','Cherchell'),
  (4215,42,'الداموس','Damous'),
  (4216,42,'مراد','Merad'),
  (4217,42,'فوكة','Fouka'),
  (4218,42,'بواسماعيل','Bou Ismail'),
  (4219,42,'أحمر العين','Ahmer El Ain'),
  (4220,42,'بوهارون','Bou Haroun'),
  (4221,42,'سيدي غيلاس','Sidi Ghiles'),
  (4222,42,'مسلمون','Messelmoun'),
  (4223,42,'سيدي راشد','Sidi Rached'),
  (4224,42,'القليعة','Kolea'),
  (4225,42,'الحطاطبة','Attatba'),
  (4226,42,'سيدي سميان','Sidi Semiane'),
  (4227,42,'بني ميلك','Beni Mileuk'),
  (4228,42,'حجرة النص','Hadjret Ennous');
update communes set is_active = true where id = 4201;   -- تيبازة المدينة فقط في البداية

-- ---------- Profiles ----------
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        user_role not null default 'customer',
  full_name   text,
  phone       text unique,
  state       account_state not null default 'active',
  customer_faults int not null default 0,
  commune_id  int references communes(id),     -- البلدية التي اختارها الزبون
  created_at  timestamptz not null default now()
);

create table stores (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references profiles(id),
  name       text not null,
  category   text not null check (category in ('restaurant','grocery','vegetables','butcher','women_clothing','men_clothing','kids_clothing','kids_supplies','electronics','phones','cosmetics','parapharmacy','bakery','fish','stationery','hardware','household','gifts','auto_parts','pets','other')),
  image_url  text,
  address    text,
  lat        double precision not null,
  lng        double precision not null,
  is_open    boolean not null default false,
  opens_at   time, closes_at time,
  state      account_state not null default 'active',
  commune_id int not null default 4201 references communes(id),   -- افتراضي تيبازة المدينة
  created_at timestamptz not null default now()
);

create table products (
  id         uuid primary key default gen_random_uuid(),
  store_id   uuid not null references stores(id) on delete cascade,
  name       text not null,
  price      numeric(10,2) not null check (price >= 0),
  image_url  text,
  available  boolean not null default true,
  script     text check (script is null or char_length(script) <= 2000)   -- سكريبت يرافق الصور والفيديو
);

-- صور وفيديوهات المنتج (الملفات في Supabase Storage داخل bucket اسمه product-media)
create table product_media (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  store_id   uuid not null references stores(id) on delete cascade,
  kind       text not null check (kind in ('image','video')),
  url        text not null,
  path       text not null,                    -- <store_id>/<product_id>/<file>
  sort       int  not null default 0,
  created_at timestamptz not null default now()
);
create index on product_media(product_id, sort);

create function product_media_guard() returns trigger language plpgsql as $$
declare sid uuid; n int;
begin
  select store_id into sid from products where id = new.product_id;
  if sid is null then raise exception 'منتج غير موجود'; end if;
  new.store_id := sid;                                           -- لا يمكن نسبة وسائط لمتجر آخر
  if new.path not like sid::text || '/%' or position(new.path in new.url) = 0 then
    raise exception 'مسار ملف غير صالح'; end if;
  select count(*) into n from product_media where product_id = new.product_id and kind = new.kind;
  if new.kind = 'image' and n >= 6 then raise exception 'الحد الأقصى 6 صور لكل منتج'; end if;
  if new.kind = 'video' and n >= 1 then raise exception 'فيديو واحد لكل منتج'; end if;
  return new;
end $$;
create trigger product_media_guard_t before insert on product_media
  for each row execute function product_media_guard();

create table couriers (
  id            uuid primary key references profiles(id),
  available     boolean not null default false,
  last_lat      double precision,
  last_lng      double precision,
  last_seen     timestamptz,
  deposit       numeric(10,2) not null default 0,    -- الضمان (اختياري)
  cash_limit    numeric(10,2)                        -- سقف النقد المفتوح (اختياري)
);

create table pricing_tiers (
  id        serial primary key,
  from_km   numeric(6,2) not null,
  to_km     numeric(6,2),            -- null = بلا حد أعلى
  fee       numeric(10,2) not null,
  extra_per_km numeric(10,2) not null default 0
);
insert into pricing_tiers(from_km,to_km,fee) values (0,3,200),(3,6,300),(6,10,400);
insert into pricing_tiers(from_km,to_km,fee,extra_per_km) values (10,null,400,40);

-- ---------- Orders ----------
create table orders (
  id              uuid primary key default gen_random_uuid(),
  type            order_type not null,
  status          order_status not null default 'new',
  customer_id     uuid not null references profiles(id),
  store_id        uuid references stores(id),
  courier_id      uuid references couriers(id),
  pickup_address  text, pickup_lat double precision, pickup_lng double precision,
  dropoff_address text not null, dropoff_lat double precision not null, dropoff_lng double precision not null,
  description     text,                         -- وصف الحاجة (p2p / free)
  free_kind       text check (free_kind in ('transfer','purchase')),
  budget          numeric(10,2),
  items_total     numeric(10,2) not null default 0,   -- ثمن المنتجات
  delivery_fee    numeric(10,2) not null,
  service_fee     numeric(10,2) not null default 0,
  distance_km     numeric(6,2) not null,
  courier_commission numeric(10,2) not null default 0,
  store_commission   numeric(10,2) not null default 0,
  commune_id      int references communes(id),   -- بلدية الطلب
  ready_at        timestamptz,
  arrived_at      timestamptz,                  -- وصول الليفرور لعنوان الزبون
  fault           fault_party,
  fault_note      text,
  cash_collected  numeric(10,2),
  created_at      timestamptz not null default now(),
  delivered_at    timestamptz,
  check ((type = 'store') = (store_id is not null))
);
create index on orders(customer_id);
create index on orders(store_id, status);
create index on orders(courier_id, status);

create table order_items (
  id         uuid primary key default gen_random_uuid(),
  order_id   uuid not null references orders(id) on delete cascade,
  product_id uuid not null references products(id),
  name       text not null,
  unit_price numeric(10,2) not null,
  qty        int not null check (qty > 0)
);

create table order_events (
  id        bigserial primary key,
  order_id  uuid not null references orders(id) on delete cascade,
  status    order_status not null,
  actor_id  uuid,
  note      text,
  at        timestamptz not null default now()
);

create table call_attempts (            -- كل ضغطة على زر الاتصال
  id         bigserial primary key,
  order_id   uuid not null references orders(id) on delete cascade,
  courier_id uuid not null references couriers(id),
  lat        double precision, lng double precision,
  at         timestamptz not null default now()
);

-- ---------- Money (append-only) ----------
create table wallet_ledger (
  id         bigserial primary key,
  courier_id uuid not null references couriers(id),
  kind       ledger_kind not null,
  amount     numeric(10,2) not null,       -- موجب = إضافة، سالب = خصم
  order_id   uuid references orders(id),
  note       text,
  created_by uuid,
  at         timestamptz not null default now()
);
create index on wallet_ledger(courier_id);

create table store_ledger (
  id         bigserial primary key,
  store_id   uuid not null references stores(id),
  kind       store_ledger_kind not null,
  amount     numeric(10,2) not null,       -- موجب = مستحق للمتجر، سالب = دُفع أو خُصم
  order_id   uuid references orders(id),
  note       text,
  created_by uuid,
  at         timestamptz not null default now()
);
create index on store_ledger(store_id);

create table topups (
  id         uuid primary key default gen_random_uuid(),
  courier_id uuid not null references couriers(id),
  amount     numeric(10,2) not null check (amount > 0),
  method     text not null check (method in ('baridimob','ccp','office')),
  proof_url  text,
  state      topup_state not null default 'pending',
  created_at timestamptz not null default now(),
  decided_at timestamptz, decided_by uuid
);

create table cash_handovers (            -- تسليم النقد للمكتب
  id         bigserial primary key,
  courier_id uuid not null references couriers(id),
  amount     numeric(10,2) not null check (amount > 0),
  received_by uuid not null,
  at         timestamptz not null default now()
);

-- append-only enforcement
create function forbid_change() returns trigger language plpgsql as $$
begin raise exception 'هذا السجل للإضافة فقط: لا تعديل ولا حذف (%).', tg_table_name; end $$;
create trigger wallet_ledger_immutable before update or delete on wallet_ledger
  for each row execute function forbid_change();
create trigger store_ledger_immutable before update or delete on store_ledger
  for each row execute function forbid_change();
create trigger order_events_immutable before update or delete on order_events
  for each row execute function forbid_change();
create trigger cash_handovers_immutable before update or delete on cash_handovers
  for each row execute function forbid_change();

-- ---------- Helpers ----------
create function setting(k text) returns numeric language sql stable as
  $$ select value from app_settings where key = k $$;

create function current_role_of() returns user_role language sql stable security definer set search_path = public as
  $$ select role from profiles where id = auth.uid() $$;

create function is_admin() returns boolean language sql stable security definer set search_path = public as
  $$ select coalesce((select role = 'admin' from profiles where id = auth.uid()), false) $$;

create function my_store_ids() returns setof uuid language sql stable security definer set search_path = public as
  $$ select id from stores where owner_id = auth.uid() $$;

create function haversine_km(lat1 double precision, lng1 double precision,
                             lat2 double precision, lng2 double precision)
returns numeric language sql immutable as $$
  select (2 * 6371 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)
  )))::numeric
$$;

create function delivery_fee_for(km numeric) returns numeric language sql stable as $$
  select fee + greatest(0, ceil(km - from_km)) * extra_per_km
  from pricing_tiers
  where km >= from_km and (to_km is null or km < to_km)
  order by from_km desc limit 1
$$;

-- عرض سعر التوصيل للزبون قبل تأكيد الطلب (نفس حساب الخادم عند إنشاء الطلب)
create function quote_delivery_fee(p_from_lat double precision, p_from_lng double precision,
                                   p_to_lat double precision, p_to_lng double precision)
returns numeric language sql stable as
  $$ select delivery_fee_for(haversine_km(p_from_lat, p_from_lng, p_to_lat, p_to_lng)) $$;

create function courier_balance(cid uuid) returns numeric language sql stable security definer set search_path = public as
  $$ select coalesce(sum(amount),0) from wallet_ledger where courier_id = cid $$;

create function store_balance(sid uuid) returns numeric language sql stable security definer set search_path = public as
  $$ select coalesce(sum(amount),0) from store_ledger where store_id = sid $$;

-- النقد المفتوح = نقد محصَّل في طلبات مُسلَّمة - ما سُلّم للمكتب
create function courier_cash_open(cid uuid) returns numeric language sql stable security definer set search_path = public as $$
  select coalesce((select sum(cash_collected) from orders where courier_id = cid and status = 'delivered'),0)
       - coalesce((select sum(amount) from cash_handovers where courier_id = cid),0)
$$;

-- ---------- New users are always customers ----------
create function handle_new_user() returns trigger language plpgsql security definer set search_path = public as $$
declare v_phone text := coalesce(new.phone, new.raw_user_meta_data->>'phone'); v_email text := to_jsonb(new)->>'email';
begin
  -- التسجيل بالهاتف فقط، وبرقم جزائري صحيح: موبيليس 06 / أوريدو 05 / جازي 07 (10 أرقام)
  if v_email is not null and v_email not like '%@phone.local' then
    raise exception 'التسجيل برقم الهاتف فقط';
  end if;
  if v_email is not null then
    if v_phone is null or v_phone !~ '^0[567][0-9]{8}$' or v_email <> v_phone || '@phone.local' then
      raise exception 'رقم هاتف جزائري غير صالح (موبيليس 06 / أوريدو 05 / جازي 07)';
    end if;
  end if;
  insert into profiles(id, role, full_name, phone)
  values (new.id, 'customer', new.raw_user_meta_data->>'full_name', v_phone);
  return new;
end $$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- ---------- Order functions ----------
create function log_event(p_order uuid, p_status order_status, p_note text default null) returns void
language sql security definer set search_path = public as
  $$ insert into order_events(order_id, status, actor_id, note) values (p_order, p_status, auth.uid(), p_note) $$;

-- إنشاء طلب من متجر واحد. الأسعار تُقرأ من قاعدة البيانات لا من التطبيق.
create function create_store_order(p_store uuid, p_items jsonb, p_addr text, p_lat double precision, p_lng double precision)
returns uuid language plpgsql security definer set search_path = public as $$
declare s stores; oid uuid; it jsonb; pr products; total numeric := 0; km numeric; fee numeric; me profiles;
begin
  select * into me from profiles where id = auth.uid();
  if me.role <> 'customer' or me.state <> 'active' then raise exception 'الحساب غير مسموح له بالطلب'; end if;
  select * into s from stores where id = p_store and is_open and state = 'active'
    and commune_id in (select id from communes where is_active);
  if not found then raise exception 'المتجر مغلق أو غير متاح'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'السلة فارغة'; end if;
  km  := haversine_km(s.lat, s.lng, p_lat, p_lng);
  fee := delivery_fee_for(km);
  insert into orders(type, customer_id, store_id, dropoff_address, dropoff_lat, dropoff_lng,
                     pickup_lat, pickup_lng, delivery_fee, distance_km, commune_id)
  values ('store', auth.uid(), p_store, p_addr, p_lat, p_lng, s.lat, s.lng, fee, round(km,2), s.commune_id)
  returning id into oid;
  for it in select * from jsonb_array_elements(p_items) loop
    select * into pr from products where id = (it->>'product_id')::uuid and store_id = p_store and available;
    if not found then raise exception 'منتج غير متوفر'; end if;
    insert into order_items(order_id, product_id, name, unit_price, qty)
    values (oid, pr.id, pr.name, pr.price, (it->>'qty')::int);
    total := total + pr.price * (it->>'qty')::int;
  end loop;
  update orders set items_total = total where id = oid;
  perform log_event(oid, 'new');
  return oid;
end $$;

-- طلب نقطة لنقطة أو طلب حر
create function create_free_order(p_type order_type, p_kind text, p_desc text, p_budget numeric,
  p_from_addr text, p_from_lat double precision, p_from_lng double precision,
  p_addr text, p_lat double precision, p_lng double precision)
returns uuid language plpgsql security definer set search_path = public as $$
declare me profiles; km numeric; fee numeric; svc numeric := 0; oid uuid;
begin
  select * into me from profiles where id = auth.uid();
  if me.role <> 'customer' or me.state <> 'active' then raise exception 'الحساب غير مسموح له بالطلب'; end if;
  if p_type not in ('p2p','free') then raise exception 'نوع طلب غير صالح'; end if;
  if me.commune_id is null or not exists (select 1 from communes where id = me.commune_id and is_active) then
    raise exception 'الخدمة غير متوفرة في بلديتك بعد'; end if;
  if p_type = 'free' and p_kind = 'purchase' then
    if p_budget is null or p_budget > setting('free_order_max_purchase') then
      raise exception 'الميزانية تتجاوز سقف الشراء (% دج)', setting('free_order_max_purchase'); end if;
    svc := setting('free_order_service_fee');
  end if;
  km  := haversine_km(p_from_lat, p_from_lng, p_lat, p_lng);
  fee := delivery_fee_for(km);
  insert into orders(type, customer_id, free_kind, description, budget, pickup_address, pickup_lat, pickup_lng,
                     dropoff_address, dropoff_lat, dropoff_lng, delivery_fee, service_fee, distance_km, commune_id)
  values (p_type, auth.uid(), case when p_type='free' then p_kind end, p_desc, p_budget,
          p_from_addr, p_from_lat, p_from_lng, p_addr, p_lat, p_lng, fee, svc, round(km,2), me.commune_id)
  returning id into oid;
  update orders set ready_at = now() where id = oid;
  perform log_event(oid, 'new');
  return oid;
end $$;

-- المتجر: قبول / رفض / تحضير / جاهز
create function store_set_status(p_order uuid, p_status order_status) returns void
language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where id = p_order;
  if not found or o.store_id not in (select my_store_ids()) then raise exception 'غير مسموح'; end if;
  if not ((o.status='new'       and p_status in ('accepted','rejected')) or
          (o.status='accepted'  and p_status = 'preparing') or
          (o.status='preparing' and p_status = 'ready')) then
    raise exception 'انتقال حالة غير صالح: % -> %', o.status, p_status; end if;
  update orders set status = p_status, ready_at = case when p_status = 'ready' then now() else ready_at end where id = p_order;
  perform log_event(p_order, p_status);
end $$;

-- الزبون: إلغاء قبل التحضير فقط
create function customer_cancel(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where id = p_order and customer_id = auth.uid();
  if not found then raise exception 'غير مسموح'; end if;
  if o.status not in ('new','accepted') then raise exception 'لا يمكن الإلغاء بعد بدء التحضير'; end if;
  update orders set status = 'cancelled' where id = p_order;
  perform log_event(p_order, 'cancelled');
end $$;

-- الليفرور: الطلبات المفتوحة مرتبة بالأقرب إلى نقطة الاستلام
create function open_orders_for_courier() returns table(order_id uuid, type order_type, status order_status,
  pickup_lat double precision, pickup_lng double precision, dropoff_lat double precision, dropoff_lng double precision,
  delivery_fee numeric, distance_to_pickup_km numeric)
language sql stable security definer set search_path = public as $$
  -- يظهر الطلب أولاً لأقرب الليفرورات المؤهلين فقط (متاح + رصيد كافٍ)، ثم للجميع بعد مدة قصيرة
  with me as (select * from couriers where id = auth.uid()),
  elig as (
    select c.id, c.last_lat, c.last_lng from couriers c join profiles p on p.id = c.id
    where c.available and p.state = 'active' and courier_balance(c.id) >= setting('min_wallet_balance'))
  select o.id, o.type, o.status, o.pickup_lat, o.pickup_lng, o.dropoff_lat, o.dropoff_lng, o.delivery_fee,
         round(haversine_km(m.last_lat, m.last_lng, o.pickup_lat, o.pickup_lng), 2)
  from orders o, me m
  where o.courier_id is null and m.available
    and ((o.type = 'store' and o.status = 'ready') or (o.type <> 'store' and o.status = 'new'))
    and (
      now() - coalesce(o.ready_at, o.created_at) > make_interval(secs => setting('dispatch_exclusive_seconds')::int)
      or (m.last_lat is not null and (
            select count(*) from elig e
            where e.id <> m.id
              and haversine_km(e.last_lat, e.last_lng, o.pickup_lat, o.pickup_lng)
                  < haversine_km(m.last_lat, m.last_lng, o.pickup_lat, o.pickup_lng)
          ) < setting('dispatch_nearest_count'))
    )
  order by 9 nulls last
$$;

create function courier_accept(p_order uuid) returns void
language plpgsql security definer set search_path = public as $$
declare c couriers; p profiles; n int;
begin
  select * into p from profiles where id = auth.uid();
  select * into c from couriers where id = auth.uid();
  if not found or p.state <> 'active' then raise exception 'غير مسموح'; end if;
  if not c.available then raise exception 'فعّل حالة "متاح" أولاً'; end if;
  if courier_balance(c.id) < setting('min_wallet_balance') then
    raise exception 'رصيدك أقل من الحد الأدنى (% دج): اشحن محفظتك', setting('min_wallet_balance'); end if;
  if setting('deposit_required') = 1 and c.cash_limit is not null and courier_cash_open(c.id) >= c.cash_limit then
    raise exception 'سلّم النقد المفتوح للمكتب أولاً'; end if;
  update orders set courier_id = c.id,
         status = case when type <> 'store' then 'ready' else status end
   where id = p_order and courier_id is null
     and ((type = 'store' and status = 'ready') or (type <> 'store' and status = 'new'));
  get diagnostics n = row_count;
  if n = 0 then raise exception 'الطلب لم يعد متاحاً'; end if;
  perform log_event(p_order, (select status from orders where id = p_order), 'courier accepted');
end $$;

-- الليفرور: استلام من المتجر / في الطريق / وصلت
create function courier_set_status(p_order uuid, p_status order_status) returns void
language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where id = p_order and courier_id = auth.uid();
  if not found then raise exception 'غير مسموح'; end if;
  if not ((o.status='ready' and p_status='picked_up') or (o.status='picked_up' and p_status='on_the_way')) then
    raise exception 'انتقال حالة غير صالح: % -> %', o.status, p_status; end if;
  update orders set status = p_status where id = p_order;
  perform log_event(p_order, p_status);
end $$;

create function courier_arrived(p_order uuid, p_lat double precision, p_lng double precision) returns void
language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where id = p_order and courier_id = auth.uid() and status = 'on_the_way';
  if not found then raise exception 'غير مسموح'; end if;
  if haversine_km(p_lat, p_lng, o.dropoff_lat, o.dropoff_lng) > 0.3 then
    raise exception 'أنت بعيد عن عنوان الزبون'; end if;
  update orders set arrived_at = coalesce(arrived_at, now()) where id = p_order;
end $$;

create function courier_log_call(p_order uuid, p_lat double precision, p_lng double precision) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from orders where id = p_order and courier_id = auth.uid()
                 and status in ('picked_up','on_the_way')) then raise exception 'غير مسموح'; end if;
  insert into call_attempts(order_id, courier_id, lat, lng) values (p_order, auth.uid(), p_lat, p_lng);
end $$;

-- التسليم: يُحصَّل النقد وتُخصم العمولات في نفس العملية
create function courier_order_contact(p_order uuid) returns table(
  customer_name text, customer_phone text, store_name text, store_phone text, calls int, arrived_at timestamptz)
language plpgsql stable security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where id = p_order and courier_id = auth.uid()
    and status in ('ready','picked_up','on_the_way');
  if not found then raise exception 'غير مسموح'; end if;
  return query
    select case when o.status in ('picked_up','on_the_way') then cp.full_name end,
           case when o.status in ('picked_up','on_the_way') then cp.phone end,
           st.name, sp.phone,
           (select count(*)::int from call_attempts ca where ca.order_id = o.id),
           o.arrived_at
    from profiles cp
    left join stores st on st.id = o.store_id
    left join profiles sp on sp.id = st.owner_id
    where cp.id = o.customer_id;
end $$;

create function courier_deliver(p_order uuid, p_cash numeric, p_items_override numeric default null) returns void
language plpgsql security definer set search_path = public as $$
declare o orders; cc numeric; sc numeric; items numeric; expected numeric;
begin
  select * into o from orders where id = p_order and courier_id = auth.uid() and status = 'on_the_way';
  if not found then raise exception 'غير مسموح'; end if;
  items := o.items_total;
  if o.type = 'free' and o.free_kind = 'purchase' then
    -- الشراء الحر: ثمن الغرض حسب فاتورة الليفرور وضمن الميزانية
    items := coalesce(p_items_override, 0);
    if items > o.budget then raise exception 'ثمن الشراء يتجاوز الميزانية'; end if;
  end if;
  expected := items + o.delivery_fee + o.service_fee;
  if p_cash <> expected then raise exception 'المبلغ المحصَّل (%) لا يساوي المطلوب (%)', p_cash, expected; end if;
  cc := round(o.delivery_fee * setting('courier_commission_rate'), 2);
  sc := case when o.type = 'store' then round(items * setting('store_commission_rate'), 2) else 0 end;
  update orders set status='delivered', delivered_at=now(), cash_collected=p_cash, items_total=items,
         courier_commission=cc, store_commission=sc where id = p_order;
  insert into wallet_ledger(courier_id, kind, amount, order_id, note)
    values (o.courier_id, 'commission', -cc, p_order, 'عمولة توصيل');
  if o.type = 'store' then
    insert into store_ledger(store_id, kind, amount, order_id, note) values (o.store_id, 'sale', items, p_order, 'ثمن المنتجات');
    if sc > 0 then insert into store_ledger(store_id, kind, amount, order_id, note)
      values (o.store_id, 'store_commission', -sc, p_order, 'عمولة المنصة'); end if;
  end if;
  perform log_event(p_order, 'delivered');
end $$;

-- تعويض الليفرور عند فشل التسليم بدون خطئه
create function pay_compensation(p_order uuid, p_courier uuid, p_fault fault_party) returns numeric
language plpgsql security definer set search_path = public as $$
declare o orders; amt numeric; paid numeric;
begin
  select * into o from orders where id = p_order;
  amt := round(o.delivery_fee * setting('compensation_rate'), 2);
  if p_fault = 'customer' then   -- سقف أسبوعي لتعويضات خطأ الزبون
    select coalesce(sum(amount),0) into paid from wallet_ledger
     where courier_id = p_courier and kind = 'compensation' and at > now() - interval '7 days';
    amt := greatest(0, least(amt, setting('compensation_weekly_cap') - paid));
  end if;
  if amt > 0 then
    insert into wallet_ledger(courier_id, kind, amount, order_id, note)
      values (p_courier, 'compensation', amt, p_order, 'تعويض: خطأ ' || p_fault);
    if p_fault = 'store' then
      insert into store_ledger(store_id, kind, amount, order_id, note)
        values (o.store_id, 'compensation_charge', -amt, p_order, 'تعويض الليفرور');
    end if;
  end if;
  return amt;
end $$;

-- تسجيل خطأ الزبون (حظر بعد خطأين)
create function register_customer_fault(p_customer uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  update profiles set customer_faults = customer_faults + 1,
         state = case when customer_faults + 1 >= setting('customer_fault_ban_after') then 'banned' else state end
   where id = p_customer;
end $$;

-- الليفرور يعلن "لم يُسلَّم". إن اكتملت الشروط → خطأ الزبون تلقائياً، وإلا → مراجعة الأدمن
create function courier_report_not_delivered(p_order uuid, p_note text default null) returns text
language plpgsql security definer set search_path = public as $$
declare o orders; calls int;
begin
  select * into o from orders where id = p_order and courier_id = auth.uid() and status in ('picked_up','on_the_way');
  if not found then raise exception 'غير مسموح'; end if;
  select count(*) into calls from call_attempts where order_id = p_order;
  if calls >= setting('required_call_attempts') and o.arrived_at is not null
     and now() - o.arrived_at >= make_interval(mins => setting('wait_minutes_at_address')::int) then
    update orders set status='not_delivered', fault='customer', fault_note=p_note where id = p_order;
    perform pay_compensation(p_order, o.courier_id, 'customer');
    perform register_customer_fault(o.customer_id);
    perform log_event(p_order, 'not_delivered', 'customer fault (auto)');
    return 'customer_fault';
  end if;
  update orders set status='dispute', fault_note=p_note where id = p_order;
  perform log_event(p_order, 'dispute', 'conditions not met: calls=' || calls);
  return 'dispute';
end $$;

-- المتجر لم يجهّز الطلب (الليفرور ينتظر): يرفع الليفرور شكوى فتُراجَع
create function courier_report_store_fault(p_order uuid, p_note text default null) returns void
language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  select * into o from orders where id = p_order and courier_id = auth.uid() and status in ('accepted','preparing','ready');
  if not found then raise exception 'غير مسموح'; end if;
  update orders set status='dispute', fault_note=p_note where id = p_order;
  perform log_event(p_order, 'dispute', 'store issue reported');
end $$;

-- الأدمن يحسم النزاع
create function admin_resolve_dispute(p_order uuid, p_fault fault_party) returns void
language plpgsql security definer set search_path = public as $$
declare o orders;
begin
  if not is_admin() then raise exception 'للأدمن فقط'; end if;
  select * into o from orders where id = p_order and status = 'dispute';
  if not found then raise exception 'الطلب ليس في نزاع'; end if;
  update orders set status='not_delivered', fault=p_fault where id = p_order;
  if p_fault = 'customer' then
    perform pay_compensation(p_order, o.courier_id, 'customer'); perform register_customer_fault(o.customer_id);
  elsif p_fault = 'store' then
    perform pay_compensation(p_order, o.courier_id, 'store');
  end if;  -- خطأ الليفرور: يتحمل الخسارة، لا تعويض
  perform log_event(p_order, 'not_delivered', 'admin resolved: ' || p_fault);
end $$;

-- ---------- Wallet / cash (admin only) ----------
create function courier_request_topup(p_amount numeric, p_method text, p_proof text default null) returns uuid
language plpgsql security definer set search_path = public as $$
declare tid uuid;
begin
  if not exists (select 1 from couriers where id = auth.uid()) then raise exception 'غير مسموح'; end if;
  insert into topups(courier_id, amount, method, proof_url) values (auth.uid(), p_amount, p_method, p_proof) returning id into tid;
  return tid;
end $$;

create function admin_decide_topup(p_topup uuid, p_confirm boolean) returns void
language plpgsql security definer set search_path = public as $$
declare t topups;
begin
  if not is_admin() then raise exception 'للأدمن فقط'; end if;
  select * into t from topups where id = p_topup and state = 'pending' for update;
  if not found then raise exception 'الطلب غير موجود أو سبق البت فيه'; end if;
  update topups set state = (case when p_confirm then 'confirmed' else 'rejected' end)::topup_state,
         decided_at = now(), decided_by = auth.uid() where id = p_topup;
  if p_confirm then
    insert into wallet_ledger(courier_id, kind, amount, note, created_by)
      values (t.courier_id, 'topup', t.amount, 'شحن محفظة', auth.uid());
  end if;
end $$;

create function admin_receive_cash(p_courier uuid, p_amount numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للأدمن فقط'; end if;
  if p_amount > courier_cash_open(p_courier) then raise exception 'المبلغ أكبر من النقد المفتوح'; end if;
  insert into cash_handovers(courier_id, amount, received_by) values (p_courier, p_amount, auth.uid());
end $$;

create function admin_pay_store(p_store uuid, p_amount numeric) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للأدمن فقط'; end if;
  if p_amount > store_balance(p_store) then raise exception 'المبلغ أكبر من مستحقات المتجر'; end if;
  insert into store_ledger(store_id, kind, amount, note, created_by)
    values (p_store, 'payout', -p_amount, 'دفع مستحقات', auth.uid());
end $$;

-- ---------- Admin: accounts ----------
create function admin_set_role(p_user uuid, p_role user_role) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للأدمن فقط'; end if;
  update profiles set role = p_role where id = p_user;
  if p_role = 'courier' then insert into couriers(id) values (p_user) on conflict do nothing; end if;
end $$;

create function admin_set_state(p_user uuid, p_state account_state) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للأدمن فقط'; end if;
  update profiles set state = p_state where id = p_user;
end $$;

create function courier_set_available(p_on boolean, p_lat double precision default null, p_lng double precision default null) returns void
language sql security definer set search_path = public as
  $$ update couriers set available = p_on, last_lat = coalesce(p_lat, last_lat), last_lng = coalesce(p_lng, last_lng),
            last_seen = now() where id = auth.uid() $$;

-- الزبون: اختيار البلدية (المفتوحة فقط)
create function set_my_commune(p_commune int) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from communes where id = p_commune and is_active) then
    raise exception 'هذه البلدية غير متاحة بعد'; end if;
  update profiles set commune_id = p_commune where id = auth.uid();
end $$;

-- الأدمن: فتح/حجب بلدية، أو ولاية كاملة
create function admin_set_commune_active(p_commune int, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للأدمن فقط'; end if;
  update communes set is_active = p_active where id = p_commune;
end $$;
create function admin_set_wilaya_active(p_wilaya int, p_active boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'للأدمن فقط'; end if;
  update communes set is_active = p_active where wilaya_id = p_wilaya;
end $$;

-- ---------- Row Level Security ----------
alter table app_settings  enable row level security;
alter table wilayas       enable row level security;
alter table communes      enable row level security;
alter table profiles      enable row level security;
alter table stores        enable row level security;
alter table products      enable row level security;
alter table product_media  enable row level security;
alter table couriers      enable row level security;
alter table pricing_tiers enable row level security;
alter table orders        enable row level security;
alter table order_items   enable row level security;
alter table order_events  enable row level security;
alter table call_attempts enable row level security;
alter table wallet_ledger enable row level security;
alter table store_ledger  enable row level security;
alter table topups        enable row level security;
alter table cash_handovers enable row level security;

-- القراءة فقط (لا توجد سياسات insert/update/delete إلا ما ذُكر صراحة)
create policy settings_read  on app_settings  for select to authenticated using (true);
create policy tiers_read     on pricing_tiers for select to authenticated using (true);
create policy profiles_self  on profiles      for select to authenticated using (id = auth.uid() or is_admin());
create policy wilayas_read   on wilayas       for select to authenticated using (true);
create policy communes_read  on communes      for select to authenticated using (true);
create policy stores_public  on stores        for select to authenticated using (
  (state = 'active' and commune_id in (select id from communes where is_active)) or owner_id = auth.uid() or is_admin());
create policy products_public on products     for select to authenticated using (true);
create policy media_read  on product_media for select to authenticated using (true);
create policy media_owner on product_media for all to authenticated
  using (store_id in (select my_store_ids()) or is_admin())
  with check (store_id in (select my_store_ids()) or is_admin());
create policy couriers_self  on couriers      for select to authenticated using (id = auth.uid() or is_admin());

-- المتجر يدير منتجاته ومتجره (ليس السعر المالي)
create policy products_owner_write on products for all to authenticated
  using (store_id in (select my_store_ids())) with check (store_id in (select my_store_ids()));
create policy stores_owner_update on stores for update to authenticated
  using (owner_id = auth.uid()) with check (owner_id = auth.uid());

create policy orders_visible on orders for select to authenticated using (
  customer_id = auth.uid() or courier_id = auth.uid() or store_id in (select my_store_ids()) or is_admin());
create policy items_visible on order_items for select to authenticated using (
  exists (select 1 from orders o where o.id = order_id));            -- يرث RLS الطلب
create policy events_visible on order_events for select to authenticated using (
  exists (select 1 from orders o where o.id = order_id));
create policy calls_visible on call_attempts for select to authenticated using (courier_id = auth.uid() or is_admin());

create policy wallet_self on wallet_ledger for select to authenticated using (courier_id = auth.uid() or is_admin());
create policy store_ledger_self on store_ledger for select to authenticated using (store_id in (select my_store_ids()) or is_admin());
create policy topups_self on topups for select to authenticated using (courier_id = auth.uid() or is_admin());
create policy handovers_self on cash_handovers for select to authenticated using (courier_id = auth.uid() or is_admin());

-- الأدمن: تعديل الإعدادات والشرائح والمتاجر
create policy settings_admin on app_settings  for update to authenticated using (is_admin()) with check (is_admin());
create policy tiers_admin    on pricing_tiers for all    to authenticated using (is_admin()) with check (is_admin());
create policy stores_admin   on stores        for all    to authenticated using (is_admin()) with check (is_admin());

-- ---------- Privileges ----------
revoke all on all tables in schema public from anon, authenticated;
revoke all on all functions in schema public from public, anon, authenticated;
grant select on all tables in schema public to authenticated;
grant insert, update, delete on products to authenticated;           -- يحكمها RLS
grant insert, update, delete on product_media to authenticated;       -- يحكمها RLS
grant update (is_open, name, address, opens_at, closes_at, image_url) on stores to authenticated;
grant insert, delete on stores to authenticated;                      -- الأدمن فقط عبر RLS
grant update on app_settings to authenticated;
grant insert, update, delete on pricing_tiers to authenticated;
grant usage, select on all sequences in schema public to authenticated;

grant execute on function
  create_store_order, create_free_order, store_set_status, customer_cancel, open_orders_for_courier,
  courier_accept, courier_set_status, courier_arrived, courier_log_call, courier_deliver,
  courier_report_not_delivered, courier_report_store_fault, courier_order_contact, admin_resolve_dispute,
  courier_request_topup, admin_decide_topup, admin_receive_cash, admin_pay_store,
  admin_set_role, admin_set_state, courier_set_available,
  set_my_commune, admin_set_commune_active, admin_set_wilaya_active,
  courier_balance, store_balance, courier_cash_open, setting, current_role_of, is_admin, my_store_ids,
  haversine_km, delivery_fee_for, quote_delivery_fee
to authenticated;
