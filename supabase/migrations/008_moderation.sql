-- RF-08: reportes, PQRS, moderación y administración

-- ===== ¿Soy administrador? (RNF-13) =====
create function public.is_admin()
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.profiles p
                 where p.id = auth.uid() and p.role = 'admin' and p.status = 'active');
$$;

-- ===== Tablas =====
create table public.reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid default auth.uid() references public.profiles(id) on delete set null,
  target_post_id uuid references public.posts(id) on delete set null,
  target_user_id uuid references public.profiles(id) on delete set null,
  reason text not null
    check (reason in ('spam', 'inappropriate', 'harassment', 'false_info', 'dangerous', 'other')),
  details text not null default '' check (char_length(details) <= 500),
  -- Copia del contenido en el momento del reporte (evidencia, RNF-25)
  snapshot jsonb not null default '{}'::jsonb,
  status text not null default 'open' check (status in ('open', 'resolved', 'dismissed')),
  action text check (action in ('none', 'post_hidden', 'user_suspended')),
  admin_note text check (char_length(admin_note) <= 500),
  reviewed_by uuid references public.profiles(id) on delete set null,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create index reports_status_idx on public.reports (status, created_at);
create index reports_post_idx on public.reports (target_post_id);
create index reports_user_idx on public.reports (target_user_id);
-- No se puede reportar dos veces lo mismo mientras siga abierto
create unique index reports_open_post_uidx on public.reports (reporter_id, target_post_id)
  where status = 'open' and target_post_id is not null;
create unique index reports_open_user_uidx on public.reports (reporter_id, target_user_id)
  where status = 'open' and target_post_id is null;

create table public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  kind text not null check (kind in ('peticion', 'queja', 'reclamo', 'sugerencia')),
  reason text not null check (char_length(reason) between 3 and 100),
  details text not null check (char_length(details) between 10 and 2000),
  attachments text[] not null default '{}',
  status text not null default 'open'
    check (status in ('open', 'in_review', 'answered', 'closed')),
  admin_response text check (char_length(admin_response) <= 1000),
  responded_by uuid references public.profiles(id) on delete set null,
  responded_at timestamptz,
  created_at timestamptz not null default now()
);
create index support_user_idx on public.support_requests (user_id, created_at desc);
create index support_status_idx on public.support_requests (status, created_at);

-- Bitácora: solo se inserta (desde las funciones), nunca se modifica ni se borra
create table public.moderation_logs (
  id uuid primary key default gen_random_uuid(),
  admin_id uuid references public.profiles(id) on delete set null,
  action text not null,
  report_id uuid references public.reports(id) on delete set null,
  target_post_id uuid,
  target_user_id uuid,
  note text,
  snapshot jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index moderation_logs_created_idx on public.moderation_logs (created_at desc);

alter table public.reports enable row level security;
alter table public.support_requests enable row level security;
alter table public.moderation_logs enable row level security;

-- ===== GRANT (capa 1): solo lectura. Nadie escribe directo en estas tablas. =====
grant select on public.reports to authenticated;
grant select on public.support_requests to authenticated;
grant select on public.moderation_logs to authenticated;
grant all on public.reports to service_role;
grant all on public.support_requests to service_role;
grant all on public.moderation_logs to service_role;

-- ===== RLS (capa 2) =====
create policy "reports_select_admin" on public.reports
  for select to authenticated using ((select public.is_admin()));

create policy "support_select_own_or_admin" on public.support_requests
  for select to authenticated
  using (user_id = (select auth.uid()) or (select public.is_admin()));

create policy "moderation_logs_select_admin" on public.moderation_logs
  for select to authenticated using ((select public.is_admin()));

-- Las cuentas suspendidas dejan de ser visibles para los demás
-- (y con ellas desaparecen sus publicaciones del feed). El admin sí las ve.
drop policy "profiles_select_visible" on public.profiles;
create policy "profiles_select_visible" on public.profiles
  for select to authenticated
  using (
    id = (select auth.uid())
    or (select public.is_admin())
    or (status = 'active'
        and not public.is_blocked_between((select auth.uid()), id))
  );

-- ===== Storage: adjuntos de PQRS (privado) =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('support-attachments', 'support-attachments', false, 3145728,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

create policy "support_att_insert_own" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'support-attachments'
              and (storage.foldername(name))[1] = (select auth.uid())::text);

create policy "support_att_select_own_or_admin" on storage.objects
  for select to authenticated
  using (bucket_id = 'support-attachments'
         and ((storage.foldername(name))[1] = (select auth.uid())::text
              or (select public.is_admin())));

create policy "support_att_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'support-attachments'
         and (storage.foldername(name))[1] = (select auth.uid())::text);

-- El admin también debe poder ver las imágenes de publicaciones reportadas u ocultas
drop policy "post_images_select_visible" on storage.objects;
create policy "post_images_select_visible" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'post-images'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or (select public.is_admin())
      or exists (select 1 from public.posts p where p.payload ->> 'image_path' = name)
    )
  );

-- ===== Usuarios: reportar =====
create function public.create_report(p_post_id uuid, p_user_id uuid,
                                     p_reason text, p_details text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_details text := trim(coalesce(p_details, ''));
  post public.posts;
  v_target uuid;
  v_name text;
  v_city text;
  snap jsonb;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if p_reason not in ('spam', 'inappropriate', 'harassment', 'false_info',
                      'dangerous', 'other') then
    raise exception 'Motivo no válido';
  end if;
  if char_length(v_details) > 500 then
    raise exception 'El detalle es demasiado largo (máximo 500 caracteres)';
  end if;
  if (p_post_id is null) = (p_user_id is null) then
    raise exception 'Indica una publicación o un usuario';
  end if;
  if (select count(*) from public.reports r
      where r.reporter_id = me and r.created_at > now() - interval '24 hours') >= 10 then
    raise exception 'Has enviado demasiados reportes hoy. Inténtalo mañana';
  end if;

  if p_post_id is not null then
    select * into post from public.posts p
    where p.id = p_post_id and p.status = 'published';
    if not found or post.author_id = me
       or not (public.are_friends(me, post.author_id)
               or public.is_post_in_my_community(p_post_id)) then
      raise exception 'No se puede reportar esta publicación';
    end if;
    v_target := post.author_id;
    select pr.first_name || ' ' || pr.last_name into v_name
    from public.profiles pr where pr.id = v_target;
    snap := jsonb_build_object(
      'kind', 'post',
      'post_type', post.type,
      'body', left(post.body, 500),
      'payload', post.payload - 'route',   -- sin el trazado: pesa mucho
      'author_id', post.author_id,
      'author_name', v_name,
      'published_at', post.published_at
    );
  else
    if p_user_id = me then raise exception 'No puedes reportarte a ti mismo'; end if;
    select pr.first_name || ' ' || pr.last_name, pr.city into v_name, v_city
    from public.profiles pr where pr.id = p_user_id;
    if not found then raise exception 'Usuario no encontrado'; end if;
    v_target := p_user_id;
    snap := jsonb_build_object('kind', 'user', 'user_name', v_name, 'city', v_city);
  end if;

  if exists (select 1 from public.reports r
             where r.reporter_id = me and r.status = 'open'
               and ((p_post_id is not null and r.target_post_id = p_post_id)
                 or (p_post_id is null and r.target_post_id is null
                     and r.target_user_id = v_target))) then
    raise exception 'Ya enviaste un reporte sobre esto. Un administrador lo revisará';
  end if;

  insert into public.reports
    (reporter_id, target_post_id, target_user_id, reason, details, snapshot)
  values (me, p_post_id, v_target, p_reason, v_details, snap);
end;
$$;

-- ===== Usuarios: PQRS =====
create function public.create_support_request(p_kind text, p_reason text,
                                              p_details text, p_attachments text[])
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_reason text := trim(coalesce(p_reason, ''));
  v_details text := trim(coalesce(p_details, ''));
  atts text[] := coalesce(p_attachments, '{}'::text[]);
  a text;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if p_kind not in ('peticion', 'queja', 'reclamo', 'sugerencia') then
    raise exception 'Tipo de solicitud no válido';
  end if;
  if char_length(v_reason) < 3 or char_length(v_reason) > 100 then
    raise exception 'La razón debe tener entre 3 y 100 caracteres';
  end if;
  if char_length(v_details) < 10 or char_length(v_details) > 2000 then
    raise exception 'El detalle debe tener entre 10 y 2000 caracteres';
  end if;
  if cardinality(atts) > 3 then raise exception 'Máximo 3 adjuntos'; end if;
  foreach a in array atts loop
    if a !~ ('^' || me::text || '/[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$') then
      raise exception 'Adjunto no válido';
    end if;
  end loop;
  if (select count(*) from public.support_requests s
      where s.user_id = me and s.created_at > now() - interval '24 hours') >= 5 then
    raise exception 'Has enviado demasiadas solicitudes hoy. Inténtalo mañana';
  end if;

  insert into public.support_requests (user_id, kind, reason, details, attachments)
  values (me, p_kind, v_reason, v_details, atts);
end;
$$;

-- ===== Suspensión (uso interno: la llaman las funciones de administración) =====
create function public.suspend_user_internal(p_user_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  update public.profiles set status = 'suspended' where id = p_user_id;
  -- Bloquea el inicio de sesión y la renovación del token
  begin
    update auth.users set banned_until = now() + interval '100 years'
    where id = p_user_id;
  exception when others then
    null;  -- si no hubiera permiso sobre auth, la app igualmente cierra la sesión
  end;
end;
$$;

-- ===== Administración =====
create function public.admin_list_reports(p_status text default 'open')
returns table (id uuid, reason text, details text, status text, action text,
               admin_note text, created_at timestamptz, reviewed_at timestamptz,
               reporter_name text, target_post_id uuid, target_user_id uuid,
               target_user_name text, target_user_status text, post_status text,
               snapshot jsonb, same_target integer)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return query
  select r.id, r.reason, r.details, r.status, r.action, r.admin_note,
         r.created_at, r.reviewed_at,
         coalesce(rp.first_name || ' ' || rp.last_name, 'Usuario eliminado'),
         r.target_post_id, r.target_user_id,
         coalesce(tu.first_name || ' ' || tu.last_name,
                  r.snapshot ->> 'author_name', r.snapshot ->> 'user_name',
                  'Usuario eliminado'),
         tu.status, po.status, r.snapshot,
         (select count(*)::int from public.reports x
          where x.status = 'open' and x.id <> r.id
            and ((r.target_post_id is not null and x.target_post_id = r.target_post_id)
              or (r.target_post_id is null and x.target_post_id is null
                  and x.target_user_id = r.target_user_id)))
  from public.reports r
  left join public.profiles rp on rp.id = r.reporter_id
  left join public.profiles tu on tu.id = r.target_user_id
  left join public.posts po on po.id = r.target_post_id
  where case when p_status = 'open' then r.status = 'open'
             else r.status <> 'open' end
  order by case when p_status = 'open' then r.created_at end asc nulls last,
           r.reviewed_at desc nulls last
  limit 100;
end;
$$;

-- p_action: 'dismiss' | 'hide_post' | 'suspend_user'
create function public.admin_resolve_report(p_report_id uuid, p_action text, p_note text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  rep public.reports;
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_status text;
  v_action text;
  v_log text;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_action not in ('dismiss', 'hide_post', 'suspend_user') then
    raise exception 'Acción no válida';
  end if;
  if v_note is not null and char_length(v_note) > 500 then
    raise exception 'La nota es demasiado larga (máximo 500 caracteres)';
  end if;

  select * into rep from public.reports r where r.id = p_report_id and r.status = 'open';
  if not found then raise exception 'El reporte no existe o ya fue revisado'; end if;

  if p_action = 'hide_post' then
    if rep.target_post_id is null then
      raise exception 'Este reporte no es de una publicación o ya no existe';
    end if;
    update public.posts set status = 'hidden'
    where id = rep.target_post_id and status = 'published';
    v_status := 'resolved'; v_action := 'post_hidden'; v_log := 'post_hidden';

  elsif p_action = 'suspend_user' then
    if rep.target_user_id is null then
      raise exception 'No hay una cuenta asociada a este reporte';
    end if;
    if rep.target_user_id = me then
      raise exception 'No puedes suspender tu propia cuenta';
    end if;
    if exists (select 1 from public.profiles p
               where p.id = rep.target_user_id and p.role = 'admin') then
      raise exception 'No se puede suspender a otro administrador';
    end if;
    perform public.suspend_user_internal(rep.target_user_id);
    v_status := 'resolved'; v_action := 'user_suspended'; v_log := 'user_suspended';

  else
    v_status := 'dismissed'; v_action := 'none'; v_log := 'report_dismissed';
  end if;

  -- Se cierra este reporte y, si hubo acción, los demás abiertos del mismo objetivo
  update public.reports r
  set status = v_status, action = v_action, admin_note = v_note,
      reviewed_by = me, reviewed_at = now()
  where r.status = 'open'
    and (r.id = p_report_id
         or (p_action = 'hide_post' and r.target_post_id = rep.target_post_id)
         or (p_action = 'suspend_user' and r.target_user_id = rep.target_user_id));

  insert into public.moderation_logs
    (admin_id, action, report_id, target_post_id, target_user_id, note, snapshot)
  values (me, v_log, p_report_id, rep.target_post_id, rep.target_user_id, v_note,
          jsonb_build_object('reason', rep.reason, 'report', rep.snapshot));
end;
$$;

create function public.admin_restore_post(p_post_id uuid, p_note text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_pub timestamptz;
  v_author uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  select p.published_at, p.author_id into v_pub, v_author
  from public.posts p where p.id = p_post_id and p.status = 'hidden';
  if not found then raise exception 'La publicación no está oculta'; end if;

  update public.posts set status = 'published' where id = p_post_id;
  -- Conserva la fecha original para que no salte al inicio del feed
  if v_pub is not null then
    update public.posts set published_at = v_pub where id = p_post_id;
  end if;

  insert into public.moderation_logs (admin_id, action, target_post_id, target_user_id, note)
  values (me, 'post_restored', p_post_id, v_author, nullif(trim(coalesce(p_note, '')), ''));
end;
$$;

create function public.admin_reactivate_user(p_user_id uuid, p_note text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare me uuid := auth.uid();
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  update public.profiles set status = 'active'
  where id = p_user_id and status = 'suspended';
  if not found then raise exception 'La cuenta no está suspendida'; end if;
  begin
    update auth.users set banned_until = null where id = p_user_id;
  exception when others then
    null;
  end;
  insert into public.moderation_logs (admin_id, action, target_user_id, note)
  values (me, 'user_reactivated', p_user_id, nullif(trim(coalesce(p_note, '')), ''));
end;
$$;

create function public.admin_list_support(p_status text default 'open')
returns table (id uuid, kind text, reason text, details text, attachments text[],
               status text, admin_response text, created_at timestamptz,
               responded_at timestamptz, user_name text)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return query
  select s.id, s.kind, s.reason, s.details, s.attachments, s.status,
         s.admin_response, s.created_at, s.responded_at,
         coalesce(pr.first_name || ' ' || pr.last_name, 'Usuario')
  from public.support_requests s
  left join public.profiles pr on pr.id = s.user_id
  where case when p_status = 'open' then s.status in ('open', 'in_review')
             else s.status in ('answered', 'closed') end
  order by s.created_at desc
  limit 100;
end;
$$;

create function public.admin_respond_support(p_id uuid, p_status text, p_response text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_resp text := nullif(trim(coalesce(p_response, '')), '');
  v_uid uuid;
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  if p_status not in ('in_review', 'answered', 'closed') then
    raise exception 'Estado no válido';
  end if;
  if v_resp is not null and char_length(v_resp) > 1000 then
    raise exception 'La respuesta es demasiado larga (máximo 1000 caracteres)';
  end if;
  if p_status = 'answered' and v_resp is null then
    raise exception 'Escribe una respuesta para el usuario';
  end if;

  update public.support_requests s
  set status = p_status,
      admin_response = coalesce(v_resp, s.admin_response),
      responded_by = me,
      responded_at = now()
  where s.id = p_id
  returning s.user_id into v_uid;
  if not found then raise exception 'Solicitud no encontrada'; end if;

  insert into public.moderation_logs (admin_id, action, target_user_id, note)
  values (me, 'support_' || p_status, v_uid, left(v_resp, 200));
end;
$$;

create function public.admin_moderation_log()
returns table (id uuid, action text, admin_name text, target_name text,
               note text, created_at timestamptz)
language plpgsql stable security definer set search_path = ''
as $$
begin
  if not public.is_admin() then raise exception 'No autorizado'; end if;
  return query
  select l.id, l.action,
         coalesce(a.first_name || ' ' || a.last_name, 'Administrador'),
         coalesce(t.first_name || ' ' || t.last_name,
                  l.snapshot -> 'report' ->> 'author_name',
                  l.snapshot -> 'report' ->> 'user_name', ''),
         l.note, l.created_at
  from public.moderation_logs l
  left join public.profiles a on a.id = l.admin_id
  left join public.profiles t on t.id = l.target_user_id
  order by l.created_at desc
  limit 100;
end;
$$;

-- ===== Retención de evidencia: 12 meses (RNF-25) =====
create function public.purge_moderation_data()
returns void
language sql security definer set search_path = ''
as $$
  delete from public.moderation_logs
  where created_at < now() - interval '12 months';
  delete from public.reports
  where status <> 'open'
    and coalesce(reviewed_at, created_at) < now() - interval '12 months';
  delete from public.support_requests
  where status = 'closed'
    and coalesce(responded_at, created_at) < now() - interval '12 months';
$$;

-- ===== EXECUTE (capa 3) =====
revoke all on function public.is_admin() from public, anon;
revoke all on function public.create_report(uuid, uuid, text, text) from public, anon;
revoke all on function public.create_support_request(text, text, text, text[]) from public, anon;
revoke all on function public.admin_list_reports(text) from public, anon;
revoke all on function public.admin_resolve_report(uuid, text, text) from public, anon;
revoke all on function public.admin_restore_post(uuid, text) from public, anon;
revoke all on function public.admin_reactivate_user(uuid, text) from public, anon;
revoke all on function public.admin_list_support(text) from public, anon;
revoke all on function public.admin_respond_support(uuid, text, text) from public, anon;
revoke all on function public.admin_moderation_log() from public, anon;
-- Estas dos no las puede llamar nadie desde la app
revoke all on function public.suspend_user_internal(uuid) from public, anon, authenticated;
revoke all on function public.purge_moderation_data() from public, anon, authenticated;

grant execute on function public.is_admin() to authenticated;
grant execute on function public.create_report(uuid, uuid, text, text) to authenticated;
grant execute on function public.create_support_request(text, text, text, text[]) to authenticated;
grant execute on function public.admin_list_reports(text) to authenticated;
grant execute on function public.admin_resolve_report(uuid, text, text) to authenticated;
grant execute on function public.admin_restore_post(uuid, text) to authenticated;
grant execute on function public.admin_reactivate_user(uuid, text) to authenticated;
grant execute on function public.admin_list_support(text) to authenticated;
grant execute on function public.admin_respond_support(uuid, text, text) to authenticated;
grant execute on function public.admin_moderation_log() to authenticated;