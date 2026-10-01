-- Tabla de perfiles: un registro por cada usuario de Supabase Auth
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null,
  last_name text not null,
  phone text,
  country text,
  city text,
  avatar_url text,
  role text not null default 'user' check (role in ('user', 'admin')),
  status text not null default 'active' check (status in ('active', 'suspended')),
  consent_accepted_at timestamptz,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- CAPA 1: GRANTs (qué puede tocar cada rol)
grant select on public.profiles to authenticated;
-- El usuario solo puede editar estas columnas (NO role, NO status):
grant update (first_name, last_name, phone, country, city, avatar_url)
  on public.profiles to authenticated;
grant all on public.profiles to service_role;

-- CAPA 2: políticas RLS (qué filas)
create policy "profiles_select_authenticated"
  on public.profiles for select to authenticated
  using (true);

create policy "profiles_update_own"
  on public.profiles for update to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Al registrarse un usuario, se crea su perfil automáticamente
-- con los datos que la app envía al registrarse
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles
    (id, first_name, last_name, phone, country, city, consent_accepted_at)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    new.raw_user_meta_data->>'phone',
    new.raw_user_meta_data->>'country',
    new.raw_user_meta_data->>'city',
    case when new.raw_user_meta_data->>'consent' = 'true' then now() end
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();