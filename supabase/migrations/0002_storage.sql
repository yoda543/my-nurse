-- Pièces justificatives des soignants : bucket privé.
-- Chemin des fichiers : <id du soignant>/<type de pièce>.<extension>
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('pro-documents', 'pro-documents', false, 5242880,
        array['image/jpeg', 'image/png', 'application/pdf']);

create policy pro_documents_upload on storage.objects for insert to authenticated
  with check (bucket_id = 'pro-documents' and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy pro_documents_read on storage.objects for select to authenticated
  using (bucket_id = 'pro-documents'
    and ((storage.foldername(name))[1] = (select auth.uid())::text or (select private.is_admin())));

create policy pro_documents_remove on storage.objects for delete to authenticated
  using (bucket_id = 'pro-documents' and (storage.foldername(name))[1] = (select auth.uid())::text);
