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
  ('deposit_required',          0,    '1 = تفعيل الضمان وسقف النقد (مغلق في التجربة)');

-- ---------- Profiles ----------
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  role        user_role not null default 'customer',
  full_name   text,
  phone       text unique,
  state       account_state not null default 'active',
  customer_faults int not null default 0,
  created_at  timestamptz not null default now()
);

create table stores (
  id         uuid primary key default gen_random_uuid(),
  owner_id   uuid not null references profiles(id),
  name       text not null,
  category   text not null check (category in ('restaurant','vegetables','butcher','grocery','clothing','electronics','other')),
  image_url  text,
  address    text,
  lat        double precision not null,
  lng        double precision not null,
  is_open    boolean not null default false,
  opens_at   time, closes_at time,
  state      account_state not null default 'active',
  created_at timestamptz not null default now()
);

create table products (
  id         uuid primary key default gen_random_uuid(),
  store_id   uuid not null references stores(id) on delete cascade,
  name       text not null,
  price      numeric(10,2) not null check (price >= 0),
  image_url  text,
  available  boolean not null default true
);

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
begin
  insert into profiles(id, role, full_name, phone)
  -- التطبيق يسجّل بإيميل وهمي (رقم الهاتف@phone.local) فيُقرأ الرقم من البيانات الوصفية
  values (new.id, 'customer', new.raw_user_meta_data->>'full_name',
          coalesce(new.phone, new.raw_user_meta_data->>'phone'));
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
  select * into s from stores where id = p_store and is_open and state = 'active';
  if not found then raise exception 'المتجر مغلق أو غير متاح'; end if;
  if jsonb_array_length(p_items) = 0 then raise exception 'السلة فارغة'; end if;
  km  := haversine_km(s.lat, s.lng, p_lat, p_lng);
  fee := delivery_fee_for(km);
  insert into orders(type, customer_id, store_id, dropoff_address, dropoff_lat, dropoff_lng,
                     pickup_lat, pickup_lng, delivery_fee, distance_km)
  values ('store', auth.uid(), p_store, p_addr, p_lat, p_lng, s.lat, s.lng, fee, round(km,2))
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
  if p_type = 'free' and p_kind = 'purchase' then
    if p_budget is null or p_budget > setting('free_order_max_purchase') then
      raise exception 'الميزانية تتجاوز سقف الشراء (% دج)', setting('free_order_max_purchase'); end if;
    svc := setting('free_order_service_fee');
  end if;
  km  := haversine_km(p_from_lat, p_from_lng, p_lat, p_lng);
  fee := delivery_fee_for(km);
  insert into orders(type, customer_id, free_kind, description, budget, pickup_address, pickup_lat, pickup_lng,
                     dropoff_address, dropoff_lat, dropoff_lng, delivery_fee, service_fee, distance_km)
  values (p_type, auth.uid(), case when p_type='free' then p_kind end, p_desc, p_budget,
          p_from_addr, p_from_lat, p_from_lng, p_addr, p_lat, p_lng, fee, svc, round(km,2))
  returning id into oid;
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
  update orders set status = p_status where id = p_order;
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
  select o.id, o.type, o.status, o.pickup_lat, o.pickup_lng, o.dropoff_lat, o.dropoff_lng, o.delivery_fee,
         round(haversine_km(c.last_lat, c.last_lng, o.pickup_lat, o.pickup_lng), 2)
  from orders o join couriers c on c.id = auth.uid()
  where o.courier_id is null and c.available
    and ((o.type = 'store' and o.status in ('accepted','preparing','ready')) or (o.type <> 'store' and o.status = 'new'))
  order by 9 nulls last
$$;

-- الليفرور: قبول طلب (الأول يربح، والرصيد يجب أن يتجاوز الحد الأدنى)
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
     and ((type = 'store' and status in ('accepted','preparing','ready')) or (type <> 'store' and status = 'new'));
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

-- ---------- Row Level Security ----------
alter table app_settings  enable row level security;
alter table profiles      enable row level security;
alter table stores        enable row level security;
alter table products      enable row level security;
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
create policy stores_public  on stores        for select to authenticated using (state = 'active' or owner_id = auth.uid() or is_admin());
create policy products_public on products     for select to authenticated using (true);
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
grant update (is_open, name, address, opens_at, closes_at, image_url) on stores to authenticated;
grant insert, delete on stores to authenticated;                      -- الأدمن فقط عبر RLS
grant update on app_settings to authenticated;
grant insert, update, delete on pricing_tiers to authenticated;
grant usage, select on all sequences in schema public to authenticated;

grant execute on function
  create_store_order, create_free_order, store_set_status, customer_cancel, open_orders_for_courier,
  courier_accept, courier_set_status, courier_arrived, courier_log_call, courier_deliver,
  courier_report_not_delivered, courier_report_store_fault, admin_resolve_dispute,
  courier_request_topup, admin_decide_topup, admin_receive_cash, admin_pay_store,
  admin_set_role, admin_set_state, courier_set_available,
  courier_balance, store_balance, courier_cash_open, setting, current_role_of, is_admin, my_store_ids,
  haversine_km, delivery_fee_for, quote_delivery_fee
to authenticated;
