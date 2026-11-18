-- يُطبَّق على Supabase مباشرة (لا يعمل في اختبارات CI لأن مخطط storage غير موجود هناك).
-- bucket عام للقراءة (روابط الصور والفيديو)، والكتابة لصاحب المتجر فقط داخل مجلد متجره: <store_id>/<product_id>/<file>
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('product-media', 'product-media', true, 52428800,
        array['image/jpeg','image/png','image/webp','video/mp4','video/quicktime','video/3gpp','video/webm'])
on conflict (id) do update set public = excluded.public, file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create policy product_media_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'product-media' and (storage.foldername(name))[1] in (select s::text from public.my_store_ids() s));
create policy product_media_update on storage.objects for update to authenticated
  using (bucket_id = 'product-media' and (storage.foldername(name))[1] in (select s::text from public.my_store_ids() s));
create policy product_media_delete on storage.objects for delete to authenticated
  using (bucket_id = 'product-media' and (storage.foldername(name))[1] in (select s::text from public.my_store_ids() s));
