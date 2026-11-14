-- بيانات تجريبية. عدّل الأرقام الثلاثة لتطابق الحسابات التي سجّلتها من التطبيق
-- (الرقم كما كتبته عند التسجيل بالضبط)، ثم شغّل الملف في SQL Editor.
do $$
declare
  admin_phone   text := '0555000001';
  courier_phone text := '0555000002';
  store_phone   text := '0555000003';
  a uuid; c uuid; s uuid; sid uuid;
begin
  select id into a from profiles where phone = admin_phone;
  select id into c from profiles where phone = courier_phone;
  select id into s from profiles where phone = store_phone;
  if a is null or c is null or s is null then
    raise exception 'لم أجد أحد الأرقام الثلاثة. سجّل الحسابات من التطبيق أولاً ثم صحّح الأرقام أعلاه.';
  end if;

  update profiles set role = 'admin'   where id = a;
  update profiles set role = 'courier' where id = c;
  update profiles set role = 'store'   where id = s;
  insert into couriers(id) values (c) on conflict do nothing;

  insert into stores(owner_id, name, category, address, lat, lng, is_open)
  values (s, 'مطعم تجريبي', 'restaurant', 'وسط تيبازة', 36.5897, 2.4475, true)
  returning id into sid;
  insert into products(store_id, name, price) values
    (sid, 'بيتزا', 800), (sid, 'ساندويتش', 350), (sid, 'عصير', 150);

  insert into stores(owner_id, name, category, address, lat, lng, is_open)
  values (s, 'متجر الخضر', 'vegetables', 'حي تجريبي', 36.5925, 2.4510, true) returning id into sid;
  insert into products(store_id, name, price) values (sid, 'طماطم 1كغ', 120), (sid, 'بطاطا 1كغ', 90), (sid, 'برتقال 1كغ', 160);
  insert into stores(owner_id, name, category, address, lat, lng, is_open)
  values (s, 'متجر الملابس', 'clothing', 'وسط تيبازة', 36.5880, 2.4440, true) returning id into sid;
  insert into products(store_id, name, price) values (sid, 'قميص', 2500), (sid, 'سروال جينز', 3500);

  -- شحن أولي للمحفظة (للتجربة فقط)
  insert into wallet_ledger(courier_id, kind, amount, note, created_by)
  values (c, 'topup', 5000, 'شحن تجريبي', a);
end $$;
