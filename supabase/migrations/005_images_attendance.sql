-- RF-03 (parte B): imagen en novedades y asistencia a rutas planeadas

-- ===== Storage: bucket privado para imágenes de publicaciones =====
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('post-images', 'post-images', false, 2097152,
        array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do nothing;

-- Cada usuario solo sube a su propia carpeta: {su_id}/archivo.jpg
create policy "post_images_insert_own" on storage.objects
  for insert to authenticated
  with check (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- Las ven el autor y sus amigos
create policy "post_images_select_friends" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'post-images'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or public.are_friends(
           (select auth.uid()),
           ((storage.foldername(name))[1])::uuid)
    )
  );

create policy "post_images_delete_own" on storage.objects
  for delete to authenticated
  using (
    bucket_id = 'post-images'
    and (storage.foldername(name))[1] = (select auth.uid())::text
  );

-- ===== Trigger: ahora las novedades aceptan image_path (RNF-20: sin ALTER TABLE) =====
-- Es la misma función de antes; solo cambia la rama 'report'.
create or replace function public.posts_before_write()
returns trigger
language plpgsql security definer set search_path = ''
as $$
declare
  p jsonb := coalesce(new.payload, '{}'::jsonb);
  a record;
  n int;
  step int;
  route_pts jsonb;
  t text;
  meeting text;
  starts timestamptz;
  publishing boolean;
  img text;
begin
  new.updated_at := now();
  new.body := trim(coalesce(new.body, ''));
  if octet_length(p::text) > 20000 then
    raise exception 'La publicación contiene demasiados datos';
  end if;

  publishing := new.status = 'published'
    and (tg_op = 'INSERT' or old.status is distinct from 'published');
  if publishing then new.published_at := now(); end if;

  if new.type = 'route_completed' then
    if new.activity_id is null then
      raise exception 'Selecciona una actividad para publicar';
    end if;
    select * into a from public.activities act
    where act.id = new.activity_id and act.user_id = new.author_id;
    if not found then
      raise exception 'La actividad aún no está sincronizada o no te pertenece';
    end if;

    n := jsonb_array_length(a.points);
    step := greatest(1, ceil(n / 150.0)::int);
    select coalesce(
             jsonb_agg(jsonb_build_array(e.val -> 0, e.val -> 1, e.val -> 5)
                       order by e.i), '[]'::jsonb)
      into route_pts
      from jsonb_array_elements(a.points) with ordinality as e(val, i)
      where (e.i - 1) % step = 0 or e.i = n;

    new.payload := jsonb_build_object(
      'activity_type', a.type,
      'distance_meters', a.distance_meters,
      'duration_seconds', a.duration_seconds,
      'elevation_gain_meters', a.elevation_gain_meters,
      'started_at', a.started_at,
      'route', route_pts
    );

  elsif new.type = 'route_planned' then
    new.activity_id := null;
    t := trim(coalesce(p ->> 'title', ''));
    meeting := trim(coalesce(p ->> 'meeting_point', ''));
    if char_length(t) > 100 then
      raise exception 'El título es demasiado largo (máximo 100 caracteres)';
    end if;
    if char_length(meeting) > 200 then
      raise exception 'El punto de encuentro es demasiado largo (máximo 200 caracteres)';
    end if;
    if coalesce(p ->> 'activity_type', 'bike') not in ('run', 'bike', 'walk') then
      raise exception 'Tipo de actividad no válido';
    end if;
    if coalesce(p ->> 'starts_at', '') <> '' then
      begin
        starts := (p ->> 'starts_at')::timestamptz;
      exception when others then
        raise exception 'La fecha y hora no son válidas';
      end;
    end if;
    if new.status = 'published' then
      if t = '' then raise exception 'Escribe un título para la ruta'; end if;
      if meeting = '' then raise exception 'Indica el punto de encuentro'; end if;
      if starts is null then raise exception 'Indica la fecha y hora de la ruta'; end if;
    end if;
    if publishing and starts <= now() then
      raise exception 'La fecha y hora de la ruta deben ser futuras';
    end if;
    new.payload := jsonb_build_object(
      'title', t,
      'meeting_point', meeting,
      'starts_at', to_jsonb(starts),
      'activity_type', coalesce(p ->> 'activity_type', 'bike')
    );

  elsif new.type = 'report' then
    new.activity_id := null;
    if coalesce(p ->> 'category', 'other')
         not in ('road_closed', 'traffic', 'hazard', 'other') then
      raise exception 'Categoría no válida';
    end if;
    if char_length(coalesce(p ->> 'location_text', '')) > 200 then
      raise exception 'La ubicación es demasiado larga (máximo 200 caracteres)';
    end if;
    if new.status = 'published' and new.body = '' then
      raise exception 'Describe la novedad';
    end if;

    -- La imagen debe estar en la carpeta del propio autor
    img := nullif(trim(coalesce(p ->> 'image_path', '')), '');
    if img is not null and img !~ ('^' || new.author_id::text
         || '/[A-Za-z0-9_-]{1,80}\.(jpg|jpeg|png|webp)$') then
      raise exception 'La imagen no es válida';
    end if;

    new.payload := jsonb_build_object(
      'category', coalesce(p ->> 'category', 'other'),
      'location_text', trim(coalesce(p ->> 'location_text', ''))
    ) || case when img is null then '{}'::jsonb
              else jsonb_build_object('image_path', img) end;
  end if;

  return new;
end;
$$;

-- ===== Asistencia a rutas planeadas =====
create table public.post_attendance (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  status text not null check (status in ('going', 'interested')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (post_id, user_id)
);
create index post_attendance_user_idx on public.post_attendance (user_id);

alter table public.post_attendance enable row level security;

-- Solo lectura directa: escribir se hace con set_attendance()
grant select on public.post_attendance to authenticated;
grant all on public.post_attendance to service_role;

-- Cada persona ve su marca; el organizador ve todas las de su ruta
create policy "attendance_select_own_or_organizer" on public.post_attendance
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.posts p
               where p.id = post_attendance.post_id
                 and p.author_id = (select auth.uid()))
  );

-- new_status: 'going' | 'interested' | 'none' (quita la marca)
create function public.set_attendance(p_post_id uuid, new_status text)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  r public.posts;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if new_status not in ('going', 'interested', 'none') then
    raise exception 'Estado no válido';
  end if;

  select * into r from public.posts p
  where p.id = p_post_id and p.type = 'route_planned' and p.status = 'published';
  if not found then
    raise exception 'La ruta no existe o ya no está disponible';
  end if;
  if r.author_id = me then
    raise exception 'Eres el organizador de esta ruta';
  end if;
  if not public.are_friends(me, r.author_id) then
    raise exception 'No puedes unirte a esta ruta';
  end if;

  if new_status = 'none' then
    delete from public.post_attendance
    where post_id = p_post_id and user_id = me;
    return;
  end if;

  if (r.payload ->> 'starts_at')::timestamptz <= now() then
    raise exception 'Esta ruta ya comenzó';
  end if;

  insert into public.post_attendance (post_id, user_id, status)
  values (p_post_id, me, new_status)
  on conflict (post_id, user_id)
  do update set status = excluded.status, updated_at = now();
end;
$$;

revoke all on function public.set_attendance(uuid, text) from public, anon;
grant execute on function public.set_attendance(uuid, text) to authenticated;

-- ===== Feed: ahora incluye tu marca y los contadores =====
-- Como la función corre con tus permisos, la RLS hace el trabajo:
-- el organizador cuenta todas las marcas; los demás solo ven la suya.
drop function public.get_feed(timestamptz, int);

create function public.get_feed(older_than timestamptz default null,
                                page_size int default 15)
returns table (id uuid, author_id uuid, author_name text, type text,
               body text, activity_id uuid, payload jsonb,
               published_at timestamptz, like_count bigint,
               comment_count bigint, liked_by_me boolean,
               my_attendance text, going_count bigint,
               interested_count bigint)
language sql stable set search_path = ''
as $$
  select p.id, p.author_id, pr.first_name || ' ' || pr.last_name,
         p.type, p.body, p.activity_id, p.payload, p.published_at,
         (select count(*) from public.post_likes l where l.post_id = p.id),
         (select count(*) from public.post_comments c where c.post_id = p.id),
         exists (select 1 from public.post_likes l
                 where l.post_id = p.id and l.user_id = auth.uid()),
         (select a.status from public.post_attendance a
          where a.post_id = p.id and a.user_id = auth.uid()),
         (select count(*) from public.post_attendance a
          where a.post_id = p.id and a.status = 'going'),
         (select count(*) from public.post_attendance a
          where a.post_id = p.id and a.status = 'interested')
  from public.posts p
  join public.profiles pr on pr.id = p.author_id
  where p.status = 'published'
    and (older_than is null or p.published_at < older_than)
  order by p.published_at desc
  limit least(greatest(page_size, 1), 30);
$$;
revoke all on function public.get_feed(timestamptz, int) from public, anon;
grant execute on function public.get_feed(timestamptz, int) to authenticated;