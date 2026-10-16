-- PostGIS: tipos y funciones geográficas (se instala en el esquema "extensions")
create extension if not exists postgis with schema extensions;

create table public.activities (
  id uuid primary key,  -- lo genera el celular: permite reintentos sin duplicar
  user_id uuid not null references public.profiles(id) on delete cascade,
  type text not null check (type in ('run', 'bike', 'walk')),
  started_at timestamptz not null,
  ended_at timestamptz not null,
  duration_seconds integer not null check (duration_seconds >= 0),
  distance_meters double precision not null check (distance_meters >= 0),
  elevation_gain_meters double precision not null default 0
    check (elevation_gain_meters >= 0),
  route extensions.geography(LineString, 4326),  -- trazado, para desafíos (RF-06)
  points jsonb not null default '[]'::jsonb,     -- [lat, lng, alt, precisión, ms, tramo]
  created_at timestamptz not null default now()
);

create index activities_user_started_idx
  on public.activities (user_id, started_at desc);
create index activities_route_gix
  on public.activities using gist (route);

alter table public.activities enable row level security;

-- CAPA 1: GRANTs. Por ahora solo leer e insertar (sin update ni delete).
grant select, insert on public.activities to authenticated;
grant all on public.activities to service_role;

-- CAPA 2: RLS. Cada usuario solo ve e inserta lo suyo.
create policy "activities_select_own"
  on public.activities for select to authenticated
  using (user_id = (select auth.uid()));

create policy "activities_insert_own"
  on public.activities for insert to authenticated
  with check (user_id = (select auth.uid()));