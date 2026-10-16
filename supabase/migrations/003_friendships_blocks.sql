-- RF-07: amistades, bloqueos y búsqueda de usuarios

-- Para buscar "Jose" y encontrar "José"
create extension if not exists unaccent with schema extensions;

-- ===== Tablas =====
create table public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles(id) on delete cascade,
  addressee_id uuid not null references public.profiles(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'accepted')),
  created_at timestamptz not null default now(),
  responded_at timestamptz,
  check (requester_id <> addressee_id)
);

-- Una sola fila por pareja, sin importar quién envió la solicitud
create unique index friendships_pair_uidx on public.friendships
  (least(requester_id, addressee_id), greatest(requester_id, addressee_id));
create index friendships_requester_idx on public.friendships (requester_id);
create index friendships_addressee_idx on public.friendships (addressee_id);

create table public.blocks (
  blocker_id uuid not null references public.profiles(id) on delete cascade,
  blocked_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id),
  check (blocker_id <> blocked_id)
);

alter table public.friendships enable row level security;
alter table public.blocks enable row level security;

-- ===== GRANT (capa 1): solo lectura directa; escribir es vía funciones =====
grant select on public.friendships to authenticated;
grant select on public.blocks to authenticated;
grant all on public.friendships to service_role;
grant all on public.blocks to service_role;

-- ===== RLS (capa 2) =====
create policy "friendships_select_own"
  on public.friendships for select to authenticated
  using (requester_id = (select auth.uid()) or addressee_id = (select auth.uid()));

create policy "blocks_select_own"
  on public.blocks for select to authenticated
  using (blocker_id = (select auth.uid()));

-- ===== Función auxiliar: ¿hay un bloqueo entre A y B (en cualquier sentido)? =====
-- SECURITY DEFINER: así quien fue bloqueado no puede ver que lo bloquearon,
-- pero las políticas y funciones sí pueden consultarlo.
create function public.is_blocked_between(a uuid, b uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.blocks
    where (blocker_id = a and blocked_id = b)
       or (blocker_id = b and blocked_id = a)
  );
$$;

-- Los perfiles de usuarios bloqueados (en cualquier sentido) dejan de ser visibles
drop policy "profiles_select_authenticated" on public.profiles;
create policy "profiles_select_visible"
  on public.profiles for select to authenticated
  using (
    id = (select auth.uid())
    or not public.is_blocked_between((select auth.uid()), id)
  );

-- ===== Acciones =====
create function public.send_friend_request(target_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  existing public.friendships;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if target_id is null or target_id = me then
    raise exception 'Solicitud no válida';
  end if;
  if not exists (select 1 from public.profiles p
                 where p.id = target_id and p.status = 'active') then
    raise exception 'Usuario no encontrado';
  end if;
  if public.is_blocked_between(me, target_id) then
    raise exception 'No es posible enviar la solicitud';
  end if;

  select * into existing from public.friendships f
  where (f.requester_id = me and f.addressee_id = target_id)
     or (f.requester_id = target_id and f.addressee_id = me);

  if found then
    if existing.status = 'accepted' then
      raise exception 'Ya son amigos';
    elsif existing.requester_id = me then
      raise exception 'Ya enviaste una solicitud a este usuario';
    else
      -- La otra persona ya te había enviado una: se acepta directamente
      update public.friendships
      set status = 'accepted', responded_at = now()
      where id = existing.id;
      return;
    end if;
  end if;

  insert into public.friendships (requester_id, addressee_id)
  values (me, target_id);
end;
$$;

create function public.respond_friend_request(request_id uuid, accept boolean)
returns void
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  req public.friendships;
begin
  select * into req from public.friendships f
  where f.id = request_id and f.addressee_id = me and f.status = 'pending';
  if not found then raise exception 'Solicitud no encontrada'; end if;

  if accept then
    update public.friendships
    set status = 'accepted', responded_at = now()
    where id = req.id;
  else
    delete from public.friendships where id = req.id;  -- rechazada
  end if;
end;
$$;

-- Elimina una amistad, o cancela una solicitud que tú enviaste
create function public.remove_friendship(other_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare me uuid := auth.uid();
begin
  delete from public.friendships f
  where ((f.requester_id = me and f.addressee_id = other_id)
      or (f.requester_id = other_id and f.addressee_id = me))
    and (f.status = 'accepted' or f.requester_id = me);
end;
$$;

create function public.block_user(target_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
declare me uuid := auth.uid();
begin
  if me is null then raise exception 'No autenticado'; end if;
  if target_id is null or target_id = me then
    raise exception 'Operación no válida';
  end if;
  if not exists (select 1 from public.profiles p where p.id = target_id) then
    raise exception 'Usuario no encontrado';
  end if;

  insert into public.blocks (blocker_id, blocked_id)
  values (me, target_id)
  on conflict do nothing;

  -- Al bloquear se elimina cualquier amistad o solicitud entre ambos
  delete from public.friendships f
  where (f.requester_id = me and f.addressee_id = target_id)
     or (f.requester_id = target_id and f.addressee_id = me);
end;
$$;

create function public.unblock_user(target_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  delete from public.blocks
  where blocker_id = auth.uid() and blocked_id = target_id;
end;
$$;

-- ===== Consultas =====
-- Amigos, solicitudes recibidas y enviadas del usuario actual
create function public.my_relationships()
returns table (user_id uuid, first_name text, last_name text, city text,
               relation text, request_id uuid)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.first_name, p.last_name, p.city,
         case when f.status = 'accepted' then 'friend'
              when f.requester_id = auth.uid() then 'outgoing'
              else 'incoming' end,
         f.id
  from public.friendships f
  join public.profiles p
    on p.id = case when f.requester_id = auth.uid()
                   then f.addressee_id else f.requester_id end
  where f.requester_id = auth.uid() or f.addressee_id = auth.uid()
  order by p.first_name, p.last_name;
$$;

create function public.my_blocked_users()
returns table (user_id uuid, first_name text, last_name text, city text)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.first_name, p.last_name, p.city
  from public.blocks b
  join public.profiles p on p.id = b.blocked_id
  where b.blocker_id = auth.uid()
  order by b.created_at desc;
$$;

-- Búsqueda por nombre completo, sin distinguir mayúsculas ni tildes.
-- Excluye a quien eres tú y a cualquier usuario con bloqueo entre ambos.
create function public.search_users(term text)
returns table (user_id uuid, first_name text, last_name text, city text,
               relation text, request_id uuid)
language sql stable security definer set search_path = ''
as $$
  select p.id, p.first_name, p.last_name, p.city,
         case when f.id is null then 'none'
              when f.status = 'accepted' then 'friend'
              when f.requester_id = auth.uid() then 'outgoing'
              else 'incoming' end,
         f.id
  from public.profiles p
  left join public.friendships f
    on (f.requester_id = p.id and f.addressee_id = auth.uid())
    or (f.addressee_id = p.id and f.requester_id = auth.uid())
  where p.id <> auth.uid()
    and p.status = 'active'
    and not public.is_blocked_between(auth.uid(), p.id)
    and length(trim(term)) >= 2
    and extensions.unaccent('extensions.unaccent'::regdictionary,
                            p.first_name || ' ' || p.last_name)
        ilike '%' || extensions.unaccent('extensions.unaccent'::regdictionary,
          replace(replace(replace(trim(term), '\', '\\'), '%', '\%'), '_', '\_'))
        || '%'
  order by p.first_name, p.last_name
  limit 30;
$$;

-- ===== EXECUTE (capa 3): solo usuarios con sesión pueden llamar las funciones =====
revoke all on function public.is_blocked_between(uuid, uuid) from public, anon;
revoke all on function public.send_friend_request(uuid) from public, anon;
revoke all on function public.respond_friend_request(uuid, boolean) from public, anon;
revoke all on function public.remove_friendship(uuid) from public, anon;
revoke all on function public.block_user(uuid) from public, anon;
revoke all on function public.unblock_user(uuid) from public, anon;
revoke all on function public.my_relationships() from public, anon;
revoke all on function public.my_blocked_users() from public, anon;
revoke all on function public.search_users(text) from public, anon;

grant execute on function public.is_blocked_between(uuid, uuid) to authenticated;
grant execute on function public.send_friend_request(uuid) to authenticated;
grant execute on function public.respond_friend_request(uuid, boolean) to authenticated;
grant execute on function public.remove_friendship(uuid) to authenticated;
grant execute on function public.block_user(uuid) to authenticated;
grant execute on function public.unblock_user(uuid) to authenticated;
grant execute on function public.my_relationships() to authenticated;
grant execute on function public.my_blocked_users() to authenticated;
grant execute on function public.search_users(text) to authenticated;