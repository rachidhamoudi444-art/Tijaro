-- Run: psql -v ON_ERROR_STOP=1 -d t -f tests/01_flow_and_security.sql
-- Each DO block raises on a failed assertion, so the script stops at the first failure.
\set QUIET on
\set VERBOSITY terse

-- ---------- helpers ----------
create function t_login(u uuid) returns void language plpgsql as $$
begin perform set_config('request.jwt.claim.sub', u::text, false); execute 'set role authenticated'; end $$;
create function t_logout() returns void language plpgsql as $$
begin execute 'reset role'; perform set_config('request.jwt.claim.sub', '', false); end $$;
-- يتأكد أن العبارة تفشل (مع جزء من رسالة الخطأ اختيارياً)
create function t_expect_fail(sql text, must_contain text default '') returns void language plpgsql as $$
declare ok boolean := true;
begin
  begin execute sql; exception when others then
    ok := false;
    if must_contain <> '' and position(must_contain in sqlerrm) = 0 then
      raise exception 'فشلت العبارة لكن برسالة غير متوقعة: % (المتوقع يحوي: %)', sqlerrm, must_contain; end if;
  end;
  if ok then raise exception 'كان يجب أن تفشل العبارة: %', sql; end if;
end $$;
grant execute on function t_login, t_logout, t_expect_fail to public;
grant usage on schema public to authenticated;

-- ---------- fixtures (as superuser) ----------
insert into auth.users(id, phone) values
 ('00000000-0000-0000-0000-0000000000a1','ad'),('00000000-0000-0000-0000-0000000000c1','c1'),
 ('00000000-0000-0000-0000-0000000000c2','c2'),('00000000-0000-0000-0000-0000000000d1','st'),
 ('00000000-0000-0000-0000-0000000000e1','cr1'),('00000000-0000-0000-0000-0000000000e2','cr2'),
 ('00000000-0000-0000-0000-0000000000e3','cr3_poor');
update profiles set role='admin' where id='00000000-0000-0000-0000-0000000000a1';
update profiles set role='store' where id='00000000-0000-0000-0000-0000000000d1';
update profiles set role='courier' where id in ('00000000-0000-0000-0000-0000000000e1','00000000-0000-0000-0000-0000000000e2','00000000-0000-0000-0000-0000000000e3');
insert into couriers(id, available, last_lat, last_lng) values
 ('00000000-0000-0000-0000-0000000000e1', true, 36.590, 2.448),
 ('00000000-0000-0000-0000-0000000000e2', true, 36.600, 2.450),
 ('00000000-0000-0000-0000-0000000000e3', true, 36.590, 2.448);
insert into stores(id, owner_id, name, category, lat, lng, is_open) values
 ('00000000-0000-0000-0000-00000000f001','00000000-0000-0000-0000-0000000000d1','مطعم تجريبي','restaurant',36.5897,2.4475,true);
insert into products(id, store_id, name, price) values
 ('00000000-0000-0000-0000-00000000b001','00000000-0000-0000-0000-00000000f001','بيتزا',800),
 ('00000000-0000-0000-0000-00000000b002','00000000-0000-0000-0000-00000000f001','عصير',150);
-- شحن أولي للليفرورات 1 و2 (e3 يبقى بلا رصيد)
insert into wallet_ledger(courier_id, kind, amount, note) values
 ('00000000-0000-0000-0000-0000000000e1','topup',3000,'seed'),
 ('00000000-0000-0000-0000-0000000000e2','topup',3000,'seed');

-- ---------- 1) الأمان: لا كتابة مباشرة على الجداول المالية والطلبات ----------
do $$ begin
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform t_expect_fail($q$insert into wallet_ledger(courier_id,kind,amount) values ('00000000-0000-0000-0000-0000000000e1','topup',99999)$q$, 'permission denied');
  perform t_expect_fail($q$update wallet_ledger set amount = 99999$q$, 'permission denied');
  perform t_expect_fail($q$update couriers set deposit = 99999 where id = auth.uid()$q$, 'permission denied');
  perform t_expect_fail($q$update profiles set role='admin' where id = auth.uid()$q$, 'permission denied');
  update app_settings set value = 0 where key='courier_commission_rate';   -- RLS: صفر صفوف تتأثر بصمت
  assert (select value from app_settings where key='courier_commission_rate') = 0.10, 'الليفرور لا يغيّر العمولة';
  update pricing_tiers set fee = 1;
  assert (select min(fee) from pricing_tiers) = 200, 'الليفرور لا يغيّر الأسعار';
  perform t_expect_fail($q$select admin_decide_topup(gen_random_uuid(), true)$q$, 'للأدمن فقط');
  perform t_expect_fail($q$select admin_set_role(auth.uid(), 'admin')$q$, 'للأدمن فقط');
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000c1');
  perform t_expect_fail($q$insert into orders(type,customer_id,dropoff_address,dropoff_lat,dropoff_lng,delivery_fee,distance_km) values ('p2p',auth.uid(),'x',0,0,0,0)$q$, 'permission denied');
  perform t_logout();
  raise notice 'OK 1: لا كتابة مباشرة على الطلبات والمحافظ والأدوار';
end $$;

-- ---------- 2) شحن المحفظة ----------
do $$ declare tid uuid; b numeric; begin
  perform t_login('00000000-0000-0000-0000-0000000000e3');
  tid := courier_request_topup(2000, 'baridimob', 'proof.jpg');
  assert courier_balance(auth.uid()) = 0, 'الرصيد لا يزيد قبل تأكيد الأدمن';
  perform t_expect_fail(format('select courier_accept(%L)', gen_random_uuid()), 'رصيدك أقل من الحد الأدنى');
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000a1');
  perform admin_decide_topup(tid, true);
  perform t_expect_fail(format('select admin_decide_topup(%L, true)', tid), 'سبق البت');   -- لا شحن مزدوج
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000e3');
  assert courier_balance(auth.uid()) = 2000, 'الرصيد بعد التأكيد 2000';
  perform t_logout();
  raise notice 'OK 2: شحن المحفظة بتأكيد الأدمن ولا يتكرر';
end $$;

-- ---------- 3) المسار الكامل لطلب من متجر ----------
create table t_state(k text primary key, v text);
do $$ declare oid uuid; o orders; cc numeric; begin
  perform t_login('00000000-0000-0000-0000-0000000000c1');
  oid := create_store_order('00000000-0000-0000-0000-00000000f001',
    '[{"product_id":"00000000-0000-0000-0000-00000000b001","qty":2},{"product_id":"00000000-0000-0000-0000-00000000b002","qty":1}]'::jsonb,
    'حي تجريبي', 36.6050, 2.4600);
  select * into o from orders where id = oid;
  assert o.items_total = 1750, format('ثمن المنتجات 1750، وجدت %s', o.items_total);
  assert o.delivery_fee = 200, format('سعر التوصيل لمسافة %s كم = 200، وجدت %s', o.distance_km, o.delivery_fee);
  perform t_logout();
  insert into t_state values ('order1', oid::text);

  -- المتجر
  perform t_login('00000000-0000-0000-0000-0000000000d1');
  perform t_expect_fail(format('select store_set_status(%L,''ready'')', oid), 'انتقال حالة غير صالح');
  perform store_set_status(oid,'accepted'); perform store_set_status(oid,'preparing');
  perform t_logout();

  -- قبل أن يجهّز المتجر الطلب لا يقبله أي ليفرور
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform t_expect_fail(format('select courier_accept(%L)', oid), 'لم يعد متاحاً');
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000d1');
  perform store_set_status(oid,'ready');
  perform t_logout();

  -- ليفرور أول يقبل، الثاني يفشل
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform courier_accept(oid);
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000e2');
  perform t_expect_fail(format('select courier_accept(%L)', oid), 'لم يعد متاحاً');
  perform t_expect_fail(format('select courier_set_status(%L,''picked_up'')', oid), 'غير مسموح');
  perform t_logout();

  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform courier_set_status(oid,'picked_up'); perform courier_set_status(oid,'on_the_way');
  perform t_expect_fail(format('select courier_deliver(%L, 1000)', oid), 'لا يساوي المطلوب');   -- مبلغ خاطئ
  perform courier_deliver(oid, 1950);                       -- 1750 + 200
  perform t_expect_fail(format('select courier_deliver(%L, 1950)', oid), 'غير مسموح');          -- لا تسليم مزدوج
  perform t_logout();

  select * into o from orders where id = oid;
  assert o.status = 'delivered' and o.courier_commission = 20, 'عمولة 10% من 200 = 20';
  assert courier_balance('00000000-0000-0000-0000-0000000000e1') = 2980, 'رصيد الليفرور 3000-20';
  assert store_balance('00000000-0000-0000-0000-00000000f001') = 1750, 'مستحقات المتجر 1750';
  assert courier_cash_open('00000000-0000-0000-0000-0000000000e1') = 1950, 'النقد المفتوح 1950';
  raise notice 'OK 3: المسار الكامل + العمولة + مستحقات المتجر + النقد المفتوح';
end $$;

-- ---------- 4) تسليم النقد للمكتب ودفع المتجر ----------
do $$ begin
  perform t_login('00000000-0000-0000-0000-0000000000a1');
  perform t_expect_fail($q$select admin_receive_cash('00000000-0000-0000-0000-0000000000e1', 5000)$q$, 'أكبر من النقد المفتوح');
  perform admin_receive_cash('00000000-0000-0000-0000-0000000000e1', 1950);
  assert courier_cash_open('00000000-0000-0000-0000-0000000000e1') = 0;
  perform t_expect_fail($q$select admin_pay_store('00000000-0000-0000-0000-00000000f001', 9999)$q$, 'أكبر من مستحقات');
  perform admin_pay_store('00000000-0000-0000-0000-00000000f001', 1750);
  assert store_balance('00000000-0000-0000-0000-00000000f001') = 0;
  perform t_logout();
  raise notice 'OK 4: تسليم النقد ودفع مستحقات المتجر';
end $$;

-- ---------- 5) خصوصية البيانات (RLS) ----------
do $$ declare n int; begin
  perform t_login('00000000-0000-0000-0000-0000000000c2');     -- زبون آخر
  select count(*) into n from orders; assert n = 0, 'زبون آخر لا يرى طلبات غيره';
  select count(*) into n from wallet_ledger; assert n = 0, 'الزبون لا يرى المحافظ';
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000e2');
  select count(*) into n from wallet_ledger where courier_id <> auth.uid(); assert n = 0, 'ليفرور لا يرى محفظة غيره';
  select count(*) into n from orders; assert n = 0, 'ليفرور لا يرى طلباً لم يُسند إليه';
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000d1');
  select count(*) into n from orders; assert n = 1, 'المتجر يرى طلباته';
  select count(*) into n from wallet_ledger; assert n = 0, 'المتجر لا يرى المحافظ';
  perform t_logout();
  raise notice 'OK 5: كل دور يرى بياناته فقط';
end $$;

-- ---------- 6) فشل التسليم: خطأ الزبون التلقائي وحظره بعد خطأين ----------
create function t_make_order_on_the_way(cust uuid, cour uuid) returns uuid language plpgsql as $$
declare oid uuid;
begin
  perform t_login(cust);
  oid := create_free_order('p2p', null, 'وثيقة', null, 'أ', 36.59, 2.44, 'ب', 36.60, 2.45);
  perform t_logout();
  perform t_login(cour);
  perform courier_accept(oid); perform courier_set_status(oid,'picked_up'); perform courier_set_status(oid,'on_the_way');
  perform t_logout();
  return oid;
end $$;

do $$ declare oid uuid; r text; o orders; begin
  -- بدون 3 محاولات اتصال → نزاع (لا تعويض تلقائي)
  oid := t_make_order_on_the_way('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000e1');
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform courier_log_call(oid, 36.60, 2.45);
  r := courier_report_not_delivered(oid, 'لا يرد');
  assert r = 'dispute', 'بدون 3 محاولات ووصول → نزاع';
  perform t_logout();
  assert courier_balance('00000000-0000-0000-0000-0000000000e1') = 2980, 'لا تعويض قبل حسم النزاع';

  -- الأدمن يحسم: الخطأ من الليفرور → لا تعويض
  perform t_login('00000000-0000-0000-0000-0000000000a1');
  perform admin_resolve_dispute(oid, 'courier');
  perform t_logout();
  assert courier_balance('00000000-0000-0000-0000-0000000000e1') = 2980, 'خطأ الليفرور: لا تعويض';
  assert (select customer_faults from profiles where id='00000000-0000-0000-0000-0000000000c2') = 0, 'لا يُسجل خطأ على الزبون';
  raise notice 'OK 6a: بدون إثبات كافٍ → نزاع، وخطأ الليفرور بلا تعويض';
end $$;

do $$ declare oid uuid; r text; bal0 numeric; begin
  -- خطأ الزبون التلقائي: 3 محاولات + وصول + 10 دقائق
  bal0 := courier_balance('00000000-0000-0000-0000-0000000000e1');
  oid := t_make_order_on_the_way('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000e1');
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform t_expect_fail(format('select courier_arrived(%L, 36.50, 2.30)', oid), 'بعيد عن عنوان الزبون');   -- GPS بعيد
  perform courier_arrived(oid, 36.60, 2.45);
  for i in 1..3 loop perform courier_log_call(oid, 36.60, 2.45); end loop;
  r := courier_report_not_delivered(oid);
  assert r = 'dispute', 'قبل مرور 10 دقائق → نزاع';
  perform t_logout();
  -- نعيد المحاكاة: نقدّم وقت الوصول 11 دقيقة (كسوبر يوزر) وننشئ طلباً جديداً بنفس الشروط
  oid := t_make_order_on_the_way('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000e1');
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform courier_arrived(oid, 36.60, 2.45);
  for i in 1..3 loop perform courier_log_call(oid, 36.60, 2.45); end loop;
  perform t_logout();
  update orders set arrived_at = now() - interval '11 minutes' where id = oid;
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  r := courier_report_not_delivered(oid, 'الزبون لا يرد');
  perform t_logout();
  assert r = 'customer_fault', 'الشروط مكتملة → خطأ الزبون';
  assert courier_balance('00000000-0000-0000-0000-0000000000e1') = bal0 + 100, 'تعويض = نصف سعر التوصيل (100)';
  assert (select customer_faults from profiles where id='00000000-0000-0000-0000-0000000000c2') = 1;
  assert (select state from profiles where id='00000000-0000-0000-0000-0000000000c2') = 'active';
  raise notice 'OK 6b: خطأ الزبون التلقائي + تعويض نصف سعر التوصيل';
end $$;

do $$ declare oid uuid; begin
  -- الخطأ الثاني → حظر الزبون
  oid := t_make_order_on_the_way('00000000-0000-0000-0000-0000000000c2','00000000-0000-0000-0000-0000000000e1');
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform courier_report_not_delivered(oid, 'x');   -- نزاع
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000a1');
  perform admin_resolve_dispute(oid, 'customer');
  perform t_logout();
  assert (select state from profiles where id='00000000-0000-0000-0000-0000000000c2') = 'banned', 'محظور بعد خطأين';
  perform t_login('00000000-0000-0000-0000-0000000000c2');
  perform t_expect_fail($q$select create_free_order('p2p', null, 'x', null, 'a', 36.59, 2.44, 'b', 36.60, 2.45)$q$, 'غير مسموح له بالطلب');
  perform t_logout();
  raise notice 'OK 6c: حظر الزبون بعد خطأين ومنعه من الطلب';
end $$;

-- ---------- 7) خطأ المتجر: تعويض الليفرور يُخصم من المتجر ----------
do $$ declare oid uuid; sb0 numeric; cb0 numeric; begin
  sb0 := store_balance('00000000-0000-0000-0000-00000000f001'); cb0 := courier_balance('00000000-0000-0000-0000-0000000000e2');
  perform t_login('00000000-0000-0000-0000-0000000000c1');
  oid := create_store_order('00000000-0000-0000-0000-00000000f001',
    '[{"product_id":"00000000-0000-0000-0000-00000000b002","qty":1}]'::jsonb, 'عنوان', 36.6050, 2.4600);
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000d1'); perform store_set_status(oid,'accepted'); perform store_set_status(oid,'preparing'); perform store_set_status(oid,'ready'); perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000e2');
  perform courier_accept(oid);
  perform courier_report_store_fault(oid, 'المتجر مغلق');
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000a1');
  perform admin_resolve_dispute(oid, 'store');
  perform t_logout();
  assert courier_balance('00000000-0000-0000-0000-0000000000e2') = cb0 + 100, 'الليفرور يُعوَّض 100';
  assert store_balance('00000000-0000-0000-0000-00000000f001') = sb0 - 100, 'المتجر يُخصم منه 100';
  raise notice 'OK 7: خطأ المتجر → تعويض الليفرور وخصمه من المتجر';
end $$;

-- ---------- 8) سجلات الإضافة فقط ----------
do $$ begin
  perform t_expect_fail($q$update wallet_ledger set amount = 1$q$, 'للإضافة فقط');          -- حتى السوبر يوزر
  perform t_expect_fail($q$delete from store_ledger$q$, 'للإضافة فقط');
  perform t_expect_fail($q$delete from order_events$q$, 'للإضافة فقط');
  raise notice 'OK 8: السجلات المالية لا تُعدَّل ولا تُحذف';
end $$;

-- ---------- 9) الطلب الحر ----------
do $$ declare oid uuid; begin
  perform t_login('00000000-0000-0000-0000-0000000000c1');
  perform t_expect_fail($q$select create_free_order('free','purchase','دواء',5000,'أ',36.59,2.44,'ب',36.60,2.45)$q$, 'تتجاوز سقف الشراء');
  oid := create_free_order('free','purchase','قلم وكراس',1000,'سوق',36.59,2.44,'بيت',36.60,2.45);
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  perform courier_accept(oid); perform courier_set_status(oid,'picked_up'); perform courier_set_status(oid,'on_the_way');
  perform t_expect_fail(format('select courier_deliver(%L, 1300, 1200)', oid), 'يتجاوز الميزانية');
  perform courier_deliver(oid, 1000 + (select delivery_fee from orders where id=oid) + 100, 1000);
  perform t_logout();
  assert (select status from orders where id = oid) = 'delivered';
  raise notice 'OK 9: الطلب الحر (سقف الشراء، الميزانية، رسوم الخدمة)';
end $$;

-- ---------- 10) عرض السعر يطابق سعر الطلب الفعلي ----------
do $$ declare q numeric; oid uuid; begin
  perform t_login('00000000-0000-0000-0000-0000000000c1');
  q := quote_delivery_fee(36.5897, 2.4475, 36.6050, 2.4600);
  oid := create_store_order('00000000-0000-0000-0000-00000000f001',
    '[{"product_id":"00000000-0000-0000-0000-00000000b002","qty":1}]'::jsonb, 'عنوان', 36.6050, 2.4600);
  assert q = (select delivery_fee from orders where id = oid), 'عرض السعر = سعر الطلب';
  perform t_logout();
  raise notice 'OK 10: عرض سعر التوصيل يطابق سعر الطلب';
end $$;

\echo ALL TESTS PASSED

-- ---------- 11) أرقام الهاتف: جزائرية فقط (موبيليس/أوريدو/جازي) ----------
do $$
begin
  insert into auth.users(id, phone, email, raw_user_meta_data)
    values (gen_random_uuid(), null, '0661234567@phone.local', '{"phone":"0661234567"}');
  begin
    insert into auth.users(id, phone, email, raw_user_meta_data)
      values (gen_random_uuid(), null, '0412345678@phone.local', '{"phone":"0412345678"}');
    raise exception 'ACCEPTED_BAD';
  exception when others then if sqlerrm = 'ACCEPTED_BAD' then raise exception 'قُبل رقم خاطئ 04'; end if; end;
  begin
    insert into auth.users(id, phone, email, raw_user_meta_data)
      values (gen_random_uuid(), null, '055123@phone.local', '{"phone":"055123"}');
    raise exception 'ACCEPTED_BAD';
  exception when others then if sqlerrm = 'ACCEPTED_BAD' then raise exception 'قُبل رقم قصير'; end if; end;
  begin
    insert into auth.users(id, phone, email, raw_user_meta_data)
      values (gen_random_uuid(), null, 'someone@gmail.com', '{"phone":"0661234568"}');
    raise exception 'ACCEPTED_BAD';
  exception when others then if sqlerrm = 'ACCEPTED_BAD' then raise exception 'قُبل بريد حقيقي'; end if; end;
  raise notice 'OK 11: أرقام الهاتف الجزائرية فقط';
end $$;

-- ---------- 12) التوزيع: الطلب الجاهز يظهر لأقرب الليفرورات أولاً ----------
do $$
declare oid uuid; n int;
begin
  perform t_login('00000000-0000-0000-0000-0000000000c1');
  oid := create_store_order('00000000-0000-0000-0000-00000000f001',
    '[{"product_id":"00000000-0000-0000-0000-00000000b002","qty":1}]'::jsonb, 'عنوان', 36.6050, 2.4600);
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000d1');
  perform store_set_status(oid,'accepted'); perform store_set_status(oid,'preparing');
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  select count(*) into n from open_orders_for_courier() where order_id = oid;
  assert n = 0, 'الطلب غير الجاهز يجب ألا يظهر للليفرور';
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000d1');
  perform store_set_status(oid,'ready');
  perform t_logout();
  perform t_login('00000000-0000-0000-0000-0000000000e1');
  select count(*) into n from open_orders_for_courier() where order_id = oid;
  assert n = 1, 'الطلب الجاهز يظهر لأقرب ليفرور';
  perform t_logout();
  raise notice 'OK 12: التوزيع على الأقرب بعد جاهزية المتجر';
end $$;
