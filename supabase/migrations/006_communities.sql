-- RF-04: comunidades (más RF-03: publicar en comunidades, RF-07: búsqueda)

-- ===== Tablas =====
create table public.communities (
  id uuid primary key default gen_random_uuid(),
  name text not null check (char_length(name) between 3 and 60),
  description text not null default '' check (char_length(description) <= 500),
  activity_type text not null default 'any'
    check (activity_type in ('any', 'run', 'bike', 'walk')),
  city text check (char_length(city) <= 80),
  is_private boolean not null default false,
  invite_code text not null unique,
  member_count integer not null default 0,
  created_by uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table public.community_members (
  community_id uuid not null references public.communities(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'member')),
  joined_at timestamptz not null default now(),
  primary key (community_id, user_id)
);
create index community_members_user_idx on public.community_members (user_id);

create table public.post_communities (
  post_id uuid not null references public.posts(id) on delete cascade,
  community_id uuid not null references public.communities(id) on delete cascade,
  primary key (post_id, community_id)
);
create index post_communities_community_idx on public.post_communities (community_id);

alter table public.communities enable row level security;
alter table public.community_members enable row level security;
alter table public.post_communities enable row level security;

-- Mantiene member_count al día (también cuando se borra un usuario en cascada)
create function public.community_members_count()
returns trigger
language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    update public.communities set member_count = member_count + 1
    where id = new.community_id;
  elsif tg_op = 'DELETE' then
    update public.communities set member_count = greatest(member_count - 1, 0)
    where id = old.community_id;
  end if;
  return null;
end;
$$;
revoke all on function public.community_members_count() from public, anon, authenticated;

create trigger community_members_count_trg
  after insert or delete on public.community_members
  for each row execute function public.community_members_count();

-- ===== Funciones auxiliares (SECURITY DEFINER: evitan recursión entre políticas) =====
create function public.is_community_member(cid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (select 1 from public.community_members m
                 where m.community_id = cid and m.user_id = uid);
$$;

-- ¿Esta publicación fue compartida en una comunidad a la que pertenezco?
create function public.is_post_in_my_community(pid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.post_communities pc
    join public.community_members m on m.community_id = pc.community_id
    where pc.post_id = pid and m.user_id = auth.uid()
  );
$$;

-- Patrón para buscar sin distinguir mayúsculas ni tildes
create function public.like_pattern(term text)
returns text
language sql stable set search_path = ''
as $$
  select '%' || extensions.unaccent('extensions.unaccent'::regdictionary,
           replace(replace(replace(trim(term), '\', '\\'), '%', '\%'), '_', '\_'))
         || '%';
$$;

-- ===== GRANT (capa 1) =====
-- Todas las columnas MENOS invite_code: el código solo lo entrega get_community()
grant select (id, name, description, activity_type, city, is_private,
              member_count, created_by, created_at)
  on public.communities to authenticated;
grant select on public.community_members to authenticated;
grant select on public.post_communities to authenticated;
grant all on public.communities to service_role;
grant all on public.community_members to service_role;
grant all on public.post_communities to service_role;

-- ===== RLS (capa 2) =====
create policy "communities_select_visible" on public.communities
  for select to authenticated
  using (not is_private or public.is_community_member(id, (select auth.uid())));

create policy "members_select" on public.community_members
  for select to authenticated
  using (user_id = (select auth.uid())
         or public.is_community_member(community_id, (select auth.uid())));

create policy "post_communities_select" on public.post_communities
  for select to authenticated
  using (
    public.is_community_member(community_id, (select auth.uid()))
    or exists (select 1 from public.posts p
               where p.id = post_communities.post_id
                 and p.author_id = (select auth.uid()))
  );

-- Los miembros de una comunidad ven las publicaciones compartidas en ella,
-- salvo las de alguien con quien hay un bloqueo
drop policy "posts_select_visible" on public.posts;
create policy "posts_select_visible" on public.posts
  for select to authenticated
  using (
    author_id = (select auth.uid())
    or (status = 'published'
        and public.are_friends((select auth.uid()), author_id))
    or (status = 'published'
        and not public.is_blocked_between((select auth.uid()), author_id)
        and public.is_post_in_my_community(id))
  );

-- Una imagen es visible si lo es la publicación que la usa (o es tuya).
-- La subconsulta pasa por la RLS de posts: amigos y comunidades quedan cubiertos.
create index posts_image_path_idx on public.posts ((payload ->> 'image_path'))
  where payload ? 'image_path';

drop policy "post_images_select_friends" on storage.objects;
create policy "post_images_select_visible" on storage.objects
  for select to authenticated
  using (
    bucket_id = 'post-images'
    and (
      (storage.foldername(name))[1] = (select auth.uid())::text
      or exists (select 1 from public.posts p
                 where p.payload ->> 'image_path' = name)
    )
  );

-- ===== Acciones =====
create function public.create_community(
  p_name text, p_description text, p_activity_type text,
  p_city text, p_is_private boolean)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_desc text := trim(coalesce(p_description, ''));
  v_city text := nullif(trim(coalesce(p_city, '')), '');
  v_type text := coalesce(p_activity_type, 'any');
  v_code text;
  v_id uuid;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if char_length(v_name) < 3 or char_length(v_name) > 60 then
    raise exception 'El nombre debe tener entre 3 y 60 caracteres';
  end if;
  if char_length(v_desc) > 500 then
    raise exception 'La descripción es demasiado larga (máximo 500 caracteres)';
  end if;
  if v_type not in ('any', 'run', 'bike', 'walk') then
    raise exception 'Tipo de actividad no válido';
  end if;
  if v_city is not null and char_length(v_city) > 80 then
    raise exception 'La ciudad es demasiado larga';
  end if;
  if (select count(*) from public.communities x where x.created_by = me) >= 10 then
    raise exception 'Has alcanzado el máximo de 10 comunidades creadas';
  end if;

  loop
    v_code := upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 10));
    exit when not exists (select 1 from public.communities x where x.invite_code = v_code);
  end loop;

  insert into public.communities
    (name, description, activity_type, city, is_private, invite_code, created_by)
  values (v_name, v_desc, v_type, v_city, coalesce(p_is_private, false), v_code, me)
  returning id into v_id;

  insert into public.community_members (community_id, user_id, role)
  values (v_id, me, 'owner');
  return v_id;
end;
$$;

create function public.join_community(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  c public.communities;
begin
  if me is null then raise exception 'No autenticado'; end if;
  select * into c from public.communities x where x.id = p_id;
  if not found then raise exception 'Comunidad no encontrada'; end if;
  if c.is_private and not public.is_community_member(p_id, me) then
    raise exception 'Esta comunidad es privada. Necesitas un código de invitación';
  end if;
  insert into public.community_members (community_id, user_id)
  values (p_id, me) on conflict do nothing;
end;
$$;

create function public.join_by_code(p_code text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  cid uuid;
begin
  if me is null then raise exception 'No autenticado'; end if;
  select x.id into cid from public.communities x
  where x.invite_code = upper(trim(coalesce(p_code, '')));
  if cid is null then raise exception 'Código de invitación no válido'; end if;
  insert into public.community_members (community_id, user_id)
  values (cid, me) on conflict do nothing;
  return cid;
end;
$$;

create function public.leave_community(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  r text;
begin
  select m.role into r from public.community_members m
  where m.community_id = p_id and m.user_id = me;
  if r is null then raise exception 'No perteneces a esta comunidad'; end if;
  if r = 'owner' then
    raise exception 'Eres el creador de la comunidad. Elimínala si quieres salir';
  end if;
  -- Tus publicaciones dejan de mostrarse en esa comunidad
  delete from public.post_communities pc
  using public.posts p
  where pc.post_id = p.id and pc.community_id = p_id and p.author_id = me;
  delete from public.community_members m
  where m.community_id = p_id and m.user_id = me;
end;
$$;

create function public.delete_community(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.communities x
                 where x.id = p_id and x.created_by = auth.uid()) then
    raise exception 'Solo el creador puede eliminar la comunidad';
  end if;
  delete from public.communities where id = p_id;
end;
$$;

-- Reemplaza las comunidades en las que se comparte una publicación (máx. 5)
create function public.set_post_communities(p_post_id uuid, p_community_ids uuid[])
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  ids uuid[] := coalesce(p_community_ids, '{}'::uuid[]);
  cid uuid;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if not exists (select 1 from public.posts p
                 where p.id = p_post_id and p.author_id = me
                   and p.status in ('draft', 'published')) then
    raise exception 'Publicación no encontrada';
  end if;

  ids := (select coalesce(array_agg(distinct x), '{}'::uuid[]) from unnest(ids) x);
  if cardinality(ids) > 5 then
    raise exception 'Máximo 5 comunidades por publicación';
  end if;
  foreach cid in array ids loop
    if not public.is_community_member(cid, me) then
      raise exception 'Solo puedes compartir en comunidades a las que perteneces';
    end if;
  end loop;

  delete from public.post_communities
  where post_id = p_post_id and not (community_id = any(ids));
  insert into public.post_communities (post_id, community_id)
  select p_post_id, x from unnest(ids) x
  on conflict do nothing;
end;
$$;

-- Marcar asistencia ahora también vale para rutas vistas por comunidad
create or replace function public.set_attendance(p_post_id uuid, new_status text)
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
  if public.is_blocked_between(me, r.author_id)
     or not (public.are_friends(me, r.author_id)
             or public.is_post_in_my_community(p_post_id)) then
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

-- ===== Consultas =====
-- Todas devuelven la misma forma para que la app use un solo modelo
create function public.my_communities()
returns table (id uuid, name text, description text, activity_type text,
               city text, is_private boolean, member_count integer,
               is_member boolean, reason text)
language sql stable set search_path = ''
as $$
  select c.id, c.name, c.description, c.activity_type, c.city, c.is_private,
         c.member_count, true, null::text
  from public.community_members m
  join public.communities c on c.id = m.community_id
  where m.user_id = auth.uid()
  order by c.name;
$$;

-- Sin SECURITY DEFINER: la RLS oculta las privadas a quien no es miembro
create function public.search_communities(term text)
returns table (id uuid, name text, description text, activity_type text,
               city text, is_private boolean, member_count integer,
               is_member boolean, reason text)
language sql stable set search_path = ''
as $$
  select c.id, c.name, c.description, c.activity_type, c.city, c.is_private,
         c.member_count, public.is_community_member(c.id, auth.uid()), null::text
  from public.communities c
  where length(trim(term)) >= 2
    and extensions.unaccent('extensions.unaccent'::regdictionary, c.name)
        ilike public.like_pattern(term)
  order by c.member_count desc, c.name
  limit 30;
$$;

-- "Comunidades para ti": reglas simples con puntos
create function public.suggested_communities(page_size int default 20)
returns table (id uuid, name text, description text, activity_type text,
               city text, is_private boolean, member_count integer,
               is_member boolean, reason text)
language sql stable security definer set search_path = ''
as $$
  with me as (
    select p.id, p.city,
           (select a.type from public.activities a
            where a.user_id = p.id
            group by a.type order by count(*) desc limit 1) as fav_type
    from public.profiles p
    where p.id = auth.uid()
  ),
  scored as (
    select c.*,
      coalesce(c.activity_type <> 'any' and c.activity_type = me.fav_type, false)
        as same_type,
      coalesce(c.city is not null and me.city is not null
               and lower(trim(c.city)) = lower(trim(me.city)), false) as same_city,
      (select count(*) from public.community_members m
        where m.community_id = c.id
          and public.are_friends(me.id, m.user_id)) as friends_in
    from public.communities c, me
    where not c.is_private
      and not exists (select 1 from public.community_members mm
                      where mm.community_id = c.id and mm.user_id = me.id)
  )
  select s.id, s.name, s.description, s.activity_type, s.city, s.is_private,
         s.member_count, false,
         nullif(concat_ws(' · ',
           case when s.same_type then 'Practican lo mismo que tú' end,
           case when s.same_city then 'En tu ciudad' end,
           case when s.friends_in > 0 then
             concat(s.friends_in, case when s.friends_in = 1
                                       then ' amigo' else ' amigos' end) end
         ), '')
  from scored s
  order by (s.same_type::int * 3 + s.same_city::int * 2 + least(s.friends_in, 3)) desc,
           s.member_count desc, s.created_at desc
  limit least(greatest(page_size, 1), 50);
$$;

-- Detalle: el código de invitación solo se entrega a los miembros
create function public.get_community(p_id uuid)
returns table (id uuid, name text, description text, activity_type text,
               city text, is_private boolean, member_count integer,
               created_by uuid, creator_name text, created_at timestamptz,
               is_member boolean, role text, invite_code text)
language sql stable security definer set search_path = ''
as $$
  select c.id, c.name, c.description, c.activity_type, c.city, c.is_private,
         c.member_count, c.created_by, pr.first_name || ' ' || pr.last_name,
         c.created_at, (m.user_id is not null), m.role,
         case when m.user_id is not null then c.invite_code end
  from public.communities c
  join public.profiles pr on pr.id = c.created_by
  left join public.community_members m
    on m.community_id = c.id and m.user_id = auth.uid()
  where c.id = p_id and (not c.is_private or m.user_id is not null);
$$;

-- ===== Feed: ahora admite comunidad y búsqueda =====
-- Sin filtros: tus publicaciones y las de tus amigos.
-- Con community_filter: las compartidas en esa comunidad.
-- Con search_term: todo lo que la RLS te deja ver.
drop function public.get_feed(timestamptz, int);

create function public.get_feed(older_than timestamptz default null,
                                page_size int default 15,
                                community_filter uuid default null,
                                search_term text default null)
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
    and case
          when community_filter is not null then exists (
            select 1 from public.post_communities pc
            where pc.post_id = p.id and pc.community_id = community_filter)
          when search_term is not null then true
          else (p.author_id = auth.uid()
                or public.are_friends(auth.uid(), p.author_id))
        end
    and (search_term is null or (
          length(trim(search_term)) >= 2
          and extensions.unaccent('extensions.unaccent'::regdictionary,
                concat_ws(' ', p.body, p.payload ->> 'title',
                          p.payload ->> 'meeting_point',
                          p.payload ->> 'location_text'))
              ilike public.like_pattern(search_term)))
  order by p.published_at desc
  limit least(greatest(page_size, 1), 30);
$$;

-- ===== EXECUTE (capa 3) =====
revoke all on function public.is_community_member(uuid, uuid) from public, anon;
revoke all on function public.is_post_in_my_community(uuid) from public, anon;
revoke all on function public.like_pattern(text) from public, anon;
revoke all on function public.create_community(text, text, text, text, boolean) from public, anon;
revoke all on function public.join_community(uuid) from public, anon;
revoke all on function public.join_by_code(text) from public, anon;
revoke all on function public.leave_community(uuid) from public, anon;
revoke all on function public.delete_community(uuid) from public, anon;
revoke all on function public.set_post_communities(uuid, uuid[]) from public, anon;
revoke all on function public.set_attendance(uuid, text) from public, anon;
revoke all on function public.my_communities() from public, anon;
revoke all on function public.search_communities(text) from public, anon;
revoke all on function public.suggested_communities(int) from public, anon;
revoke all on function public.get_community(uuid) from public, anon;
revoke all on function public.get_feed(timestamptz, int, uuid, text) from public, anon;

grant execute on function public.is_community_member(uuid, uuid) to authenticated;
grant execute on function public.is_post_in_my_community(uuid) to authenticated;
grant execute on function public.like_pattern(text) to authenticated;
grant execute on function public.create_community(text, text, text, text, boolean) to authenticated;
grant execute on function public.join_community(uuid) to authenticated;
grant execute on function public.join_by_code(text) to authenticated;
grant execute on function public.leave_community(uuid) to authenticated;
grant execute on function public.delete_community(uuid) to authenticated;
grant execute on function public.set_post_communities(uuid, uuid[]) to authenticated;
grant execute on function public.set_attendance(uuid, text) to authenticated;
grant execute on function public.my_communities() to authenticated;
grant execute on function public.search_communities(text) to authenticated;
grant execute on function public.suggested_communities(int) to authenticated;
grant execute on function public.get_community(uuid) to authenticated;
grant execute on function public.get_feed(timestamptz, int, uuid, text) to authenticated;