-- RF-03 (parte A): publicaciones, me gusta, comentarios y feed

-- ===== Tipos de publicación (RNF-20: un tipo nuevo = una fila nueva) =====
create table public.post_types (
  code text primary key,
  label text not null
);
insert into public.post_types (code, label) values
  ('route_completed', 'Ruta completada'),
  ('route_planned', 'Ruta planeada'),
  ('report', 'Novedad / reporte');

alter table public.post_types enable row level security;
grant select on public.post_types to authenticated;
grant all on public.post_types to service_role;
create policy "post_types_select" on public.post_types
  for select to authenticated using (true);

-- ===== Publicaciones =====
create table public.posts (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  type text not null references public.post_types(code),
  status text not null default 'draft'
    check (status in ('draft', 'published', 'hidden')),
  body text not null default '' check (char_length(body) <= 2000),
  activity_id uuid references public.activities(id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  published_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index posts_feed_idx on public.posts (published_at desc)
  where status = 'published';
create index posts_author_idx on public.posts (author_id, updated_at desc);

-- ===== Me gusta y comentarios =====
create table public.post_likes (
  post_id uuid not null references public.posts(id) on delete cascade,
  user_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (post_id, user_id)
);

create table public.post_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.posts(id) on delete cascade,
  author_id uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  body text not null check (char_length(trim(body)) between 1 and 500),
  created_at timestamptz not null default now()
);
create index post_comments_post_idx on public.post_comments (post_id, created_at);

alter table public.posts enable row level security;
alter table public.post_likes enable row level security;
alter table public.post_comments enable row level security;

-- ===== ¿Son amigos? (para las políticas) =====
create function public.are_friends(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.friendships f
    where f.status = 'accepted'
      and ((f.requester_id = a and f.addressee_id = b)
        or (f.requester_id = b and f.addressee_id = a))
  );
$$;
revoke all on function public.are_friends(uuid, uuid) from public, anon;
grant execute on function public.are_friends(uuid, uuid) to authenticated;

-- ===== GRANT (capa 1) =====
grant select on public.posts to authenticated;
-- author_id no se envía: lo asigna el servidor (default auth.uid()).
-- type y activity_id solo se pueden definir al crear, nunca cambiar.
grant insert (type, status, body, activity_id, payload) on public.posts to authenticated;
grant update (status, body, payload) on public.posts to authenticated;
grant delete on public.posts to authenticated;
grant all on public.posts to service_role;

grant select, delete on public.post_likes to authenticated;
grant insert (post_id) on public.post_likes to authenticated;
grant all on public.post_likes to service_role;

grant select, delete on public.post_comments to authenticated;
grant insert (post_id, body) on public.post_comments to authenticated;
grant all on public.post_comments to service_role;

-- ===== RLS (capa 2) =====
-- Ves tus publicaciones (incluidos borradores) y las publicadas por tus amigos
create policy "posts_select_visible" on public.posts
  for select to authenticated
  using (
    author_id = (select auth.uid())
    or (status = 'published'
        and public.are_friends((select auth.uid()), author_id))
  );

create policy "posts_insert_own" on public.posts
  for insert to authenticated
  with check (author_id = (select auth.uid()) and status in ('draft', 'published'));

-- Una publicación oculta por moderación ya no se puede editar ni borrar
create policy "posts_update_own" on public.posts
  for update to authenticated
  using (author_id = (select auth.uid()) and status in ('draft', 'published'))
  with check (author_id = (select auth.uid()) and status in ('draft', 'published'));

create policy "posts_delete_own" on public.posts
  for delete to authenticated
  using (author_id = (select auth.uid()) and status in ('draft', 'published'));

-- Me gusta: solo sobre publicaciones que puedes ver
create policy "likes_select_visible" on public.post_likes
  for select to authenticated
  using (exists (select 1 from public.posts p where p.id = post_likes.post_id));

create policy "likes_insert_own" on public.post_likes
  for insert to authenticated
  with check (
    user_id = (select auth.uid())
    and exists (select 1 from public.posts p
                where p.id = post_likes.post_id and p.status = 'published')
  );

create policy "likes_delete_own" on public.post_likes
  for delete to authenticated
  using (user_id = (select auth.uid()));

-- Comentarios: no se ven los de usuarios con bloqueo entre ambos
create policy "comments_select_visible" on public.post_comments
  for select to authenticated
  using (
    exists (select 1 from public.posts p where p.id = post_comments.post_id)
    and not public.is_blocked_between((select auth.uid()), author_id)
  );

create policy "comments_insert_own" on public.post_comments
  for insert to authenticated
  with check (
    author_id = (select auth.uid())
    and exists (select 1 from public.posts p
                where p.id = post_comments.post_id and p.status = 'published')
  );

-- Borra el autor del comentario o el dueño de la publicación
create policy "comments_delete_own_or_post_owner" on public.post_comments
  for delete to authenticated
  using (
    author_id = (select auth.uid())
    or exists (select 1 from public.posts p
               where p.id = post_comments.post_id
                 and p.author_id = (select auth.uid()))
  );

-- ===== Validación en el servidor (RNF-12) =====
create function public.posts_before_write()
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

    -- Versión liviana del trazado (máx. ~150 puntos): [lat, lng, tramo]
    n := jsonb_array_length(a.points);
    step := greatest(1, ceil(n / 150.0)::int);
    select coalesce(
             jsonb_agg(jsonb_build_array(e.val -> 0, e.val -> 1, e.val -> 5)
                       order by e.i), '[]'::jsonb)
      into route_pts
      from jsonb_array_elements(a.points) with ordinality as e(val, i)
      where (e.i - 1) % step = 0 or e.i = n;

    -- Las estadísticas las pone el servidor, no la app
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
    new.payload := jsonb_build_object(
      'category', coalesce(p ->> 'category', 'other'),
      'location_text', trim(coalesce(p ->> 'location_text', ''))
    );
  end if;

  return new;
end;
$$;

revoke all on function public.posts_before_write() from public, anon, authenticated;

create trigger posts_before_write
  before insert or update on public.posts
  for each row execute function public.posts_before_write();

-- ===== Feed paginado =====
-- Sin SECURITY DEFINER: se ejecuta con tus permisos, así que la RLS
-- decide qué publicaciones ves (las tuyas y las de tus amigos).
create function public.get_feed(older_than timestamptz default null,
                                page_size int default 15)
returns table (id uuid, author_id uuid, author_name text, type text,
               body text, activity_id uuid, payload jsonb,
               published_at timestamptz, like_count bigint,
               comment_count bigint, liked_by_me boolean)
language sql stable set search_path = ''
as $$
  select p.id, p.author_id, pr.first_name || ' ' || pr.last_name,
         p.type, p.body, p.activity_id, p.payload, p.published_at,
         (select count(*) from public.post_likes l where l.post_id = p.id),
         (select count(*) from public.post_comments c where c.post_id = p.id),
         exists (select 1 from public.post_likes l
                 where l.post_id = p.id and l.user_id = auth.uid())
  from public.posts p
  join public.profiles pr on pr.id = p.author_id
  where p.status = 'published'
    and (older_than is null or p.published_at < older_than)
  order by p.published_at desc
  limit least(greatest(page_size, 1), 30);
$$;
revoke all on function public.get_feed(timestamptz, int) from public, anon;
grant execute on function public.get_feed(timestamptz, int) to authenticated;