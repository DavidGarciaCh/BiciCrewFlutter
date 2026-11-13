-- RF-06: desafíos asociados a rutas, resultados y ranking

-- ===== Utilidad: versión liviana de un trazado (máx. p_max puntos) =====
-- Devuelve [[lat, lng, tramo], ...] a partir de los puntos de una actividad
create function public.route_preview(p_points jsonb, p_max int)
returns jsonb
language sql immutable set search_path = ''
as $$
  select coalesce(
           jsonb_agg(jsonb_build_array(e.val -> 0, e.val -> 1, e.val -> 5)
                     order by e.i), '[]'::jsonb)
  from jsonb_array_elements(p_points) with ordinality as e(val, i)
  where (e.i - 1) % greatest(1, ceil(jsonb_array_length(p_points) / p_max::numeric)::int) = 0
     or e.i = jsonb_array_length(p_points);
$$;

-- ===== Tablas =====
create table public.challenges (
  id uuid primary key default gen_random_uuid(),
  created_by uuid not null default auth.uid()
    references public.profiles(id) on delete cascade,
  title text not null check (char_length(title) between 3 and 80),
  description text not null default '' check (char_length(description) <= 500),
  activity_type text not null check (activity_type in ('run', 'bike', 'walk')),
  route extensions.geography(LineString, 4326) not null,
  start_point extensions.geography(Point, 4326) not null,
  end_point extensions.geography(Point, 4326) not null,
  distance_meters double precision not null check (distance_meters >= 500),
  elevation_gain_meters double precision not null default 0,
  visibility text not null default 'public' check (visibility in ('public', 'friends')),
  status text not null default 'active' check (status in ('active', 'closed')),
  source_activity_id uuid references public.activities(id) on delete set null,
  preview jsonb not null default '[]'::jsonb,   -- trazado liviano para mostrar en la app
  created_at timestamptz not null default now()
);
create index challenges_creator_idx on public.challenges (created_by);
create index challenges_status_idx on public.challenges (status, created_at desc);

create table public.challenge_results (
  id uuid primary key default gen_random_uuid(),
  challenge_id uuid not null references public.challenges(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  activity_id uuid not null references public.activities(id) on delete cascade,
  duration_seconds integer not null check (duration_seconds > 0),
  completed_at timestamptz not null,
  created_at timestamptz not null default now(),
  unique (challenge_id, activity_id)   -- una actividad solo cuenta una vez por desafío
);
create index challenge_results_rank_idx
  on public.challenge_results (challenge_id, duration_seconds);
create index challenge_results_user_idx on public.challenge_results (user_id);

alter table public.challenges enable row level security;
alter table public.challenge_results enable row level security;

-- ===== ¿Puedo ver este desafío? =====
create function public.can_view_challenge(cid uuid, uid uuid)
returns boolean
language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.challenges c
    where c.id = cid
      and (
        c.created_by = uid
        or (not public.is_blocked_between(uid, c.created_by)
            and (c.visibility = 'public' or public.are_friends(uid, c.created_by)))
      )
  );
$$;

-- ===== GRANT (capa 1) =====
-- Sin las columnas geográficas (route, start_point, end_point): no se piden desde la app
grant select (id, created_by, title, description, activity_type, distance_meters,
              elevation_gain_meters, visibility, status, preview, created_at)
  on public.challenges to authenticated;
grant select on public.challenge_results to authenticated;
grant all on public.challenges to service_role;
grant all on public.challenge_results to service_role;

-- ===== RLS (capa 2) =====
create policy "challenges_select_visible" on public.challenges
  for select to authenticated
  using (public.can_view_challenge(id, (select auth.uid())));

-- Tus propios resultados; el ranking de los demás se lee con challenge_ranking()
create policy "results_select_own" on public.challenge_results
  for select to authenticated
  using (user_id = (select auth.uid()));

-- ===== Crear un desafío a partir de una actividad sincronizada =====
create function public.create_challenge(
  p_activity_id uuid, p_title text, p_description text, p_visibility text)
returns uuid
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  a public.activities;
  v_title text := trim(coalesce(p_title, ''));
  v_desc text := trim(coalesce(p_description, ''));
  v_vis text := coalesce(p_visibility, 'public');
  line extensions.geography;
  v_id uuid;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if char_length(v_title) < 3 or char_length(v_title) > 80 then
    raise exception 'El título debe tener entre 3 y 80 caracteres';
  end if;
  if char_length(v_desc) > 500 then
    raise exception 'La descripción es demasiado larga (máximo 500 caracteres)';
  end if;
  if v_vis not in ('public', 'friends') then
    raise exception 'Visibilidad no válida';
  end if;

  select * into a from public.activities x
  where x.id = p_activity_id and x.user_id = me;
  if not found then
    raise exception 'La actividad aún no está sincronizada o no te pertenece';
  end if;
  if jsonb_array_length(a.points) < 20 then
    raise exception 'La actividad es demasiado corta para un desafío';
  end if;
  if exists (select 1 from public.challenges c where c.source_activity_id = a.id) then
    raise exception 'Ya existe un desafío creado con esta actividad';
  end if;
  if (select count(*) from public.challenges c
      where c.created_by = me and c.status = 'active') >= 10 then
    raise exception 'Has alcanzado el máximo de 10 desafíos activos';
  end if;

  -- Trazado completo en PostGIS (lng, lat)
  select extensions.ST_MakeLine(
           extensions.ST_SetSRID(
             extensions.ST_MakePoint((e.val ->> 1)::float8, (e.val ->> 0)::float8), 4326)
           order by e.i)::extensions.geography
    into line
    from jsonb_array_elements(a.points) with ordinality as e(val, i);

  if extensions.ST_Length(line) < 500 then
    raise exception 'El desafío debe tener al menos 500 m';
  end if;

  insert into public.challenges
    (created_by, title, description, activity_type, route, start_point, end_point,
     distance_meters, elevation_gain_meters, visibility, source_activity_id, preview)
  values
    (me, v_title, v_desc, a.type, line,
     extensions.ST_StartPoint(line::extensions.geometry)::extensions.geography,
     extensions.ST_EndPoint(line::extensions.geometry)::extensions.geography,
     extensions.ST_Length(line), a.elevation_gain_meters, v_vis, a.id,
     public.route_preview(a.points, 150))
  returning id into v_id;

  return v_id;
end;
$$;

create function public.delete_challenge(p_id uuid)
returns void
language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.challenges c
                 where c.id = p_id and c.created_by = auth.uid()) then
    raise exception 'Solo el creador puede eliminar el desafío';
  end if;
  delete from public.challenges where id = p_id;
end;
$$;

-- ===== Registrar un intento: aquí se valida que realmente hiciste la ruta =====
create function public.submit_challenge_attempt(p_challenge_id uuid, p_activity_id uuid)
returns jsonb
language plpgsql security definer set search_path = ''
as $$
declare
  me uuid := auth.uid();
  ch public.challenges;
  act public.activities;
  r constant float8 := 40;     -- radio de inicio y fin (m)
  tol constant float8 := 50;   -- distancia máxima a la ruta (m)
  pt_row record;
  pt extensions.geography;
  prev extensions.geography;
  d_start float8;
  state int := 0;              -- 0 = buscando inicio, 1 = avanzando
  reached_start boolean := false;
  completed boolean := false;
  cum float8 := 0;
  t_start bigint;
  t_end bigint;
  sub_pts extensions.geometry[] := '{}';
  sub_line extensions.geography;
  sub_len float8;
  ok_samples int := 0;
  k int;
  sp extensions.geography;
  v_dur int;
  max_speed float8;
  prev_best int;
  v_my_best int;
  v_pos int;
  v_total int;
begin
  if me is null then raise exception 'No autenticado'; end if;
  if not public.can_view_challenge(p_challenge_id, me) then
    raise exception 'Desafío no encontrado';
  end if;
  select * into ch from public.challenges c
  where c.id = p_challenge_id and c.status = 'active';
  if not found then raise exception 'Este desafío ya no está activo'; end if;

  select * into act from public.activities x
  where x.id = p_activity_id and x.user_id = me;
  if not found then
    raise exception 'La actividad aún no está sincronizada o no te pertenece';
  end if;
  if act.type <> ch.activity_type then
    raise exception 'Este desafío es de otro tipo de actividad';
  end if;
  if exists (select 1 from public.challenge_results x
             where x.challenge_id = p_challenge_id and x.activity_id = p_activity_id) then
    raise exception 'Esta actividad ya fue registrada en el desafío';
  end if;

  -- 1) Recorre tus puntos buscando inicio -> final
  for pt_row in
    select e.val as val
    from jsonb_array_elements(act.points) with ordinality as e(val, i)
    order by e.i
  loop
    pt := extensions.ST_SetSRID(
            extensions.ST_MakePoint((pt_row.val ->> 1)::float8, (pt_row.val ->> 0)::float8),
            4326)::extensions.geography;
    d_start := extensions.ST_Distance(pt, ch.start_point);

    if state = 0 then
      if d_start <= r then
        state := 1;
        reached_start := true;
        cum := 0;
        t_start := (pt_row.val ->> 4)::bigint;
        prev := pt;
        sub_pts := array[pt::extensions.geometry];
      end if;
      continue;
    end if;

    -- Aún en la zona de salida: el inicio es el último punto dentro del radio
    if cum < 3 * r and d_start <= r then
      cum := 0;
      t_start := (pt_row.val ->> 4)::bigint;
      prev := pt;
      sub_pts := array[pt::extensions.geometry];
      continue;
    end if;

    cum := cum + extensions.ST_Distance(prev, pt);
    prev := pt;
    sub_pts := sub_pts || pt::extensions.geometry;

    if cum > ch.distance_meters * 1.5 then
      state := 0;              -- se desvió demasiado: vuelve a buscar el inicio
      sub_pts := '{}';
      continue;
    end if;
    if cum >= ch.distance_meters * 0.7
       and extensions.ST_Distance(pt, ch.end_point) <= r then
      t_end := (pt_row.val ->> 4)::bigint;
      completed := true;
      exit;
    end if;
  end loop;

  if not completed then
    if not reached_start then
      raise exception 'Tu actividad no pasó cerca del punto de inicio del desafío';
    end if;
    raise exception 'No llegaste al final del desafío siguiendo la ruta';
  end if;

  -- 2) La distancia recorrida debe ser parecida a la del desafío
  sub_line := extensions.ST_MakeLine(sub_pts)::extensions.geography;
  sub_len := extensions.ST_Length(sub_line);
  if sub_len < ch.distance_meters * 0.7 or sub_len > ch.distance_meters * 1.4 then
    raise exception 'La distancia que recorriste no coincide con la del desafío';
  end if;

  -- 3) Debes haber seguido la ruta: 21 puntos de control a lo largo del trazado
  for k in 0..20 loop
    sp := extensions.ST_LineInterpolatePoint(
            ch.route::extensions.geometry, (k / 20.0)::float8)::extensions.geography;
    if extensions.ST_DWithin(sp, sub_line, tol) then
      ok_samples := ok_samples + 1;
    end if;
  end loop;
  if ok_samples < 19 then
    raise exception 'Te alejaste de la ruta del desafío (cubriste % de 21 puntos de control; se necesitan al menos 19)', ok_samples;
  end if;

  -- 4) Velocidad plausible para el tipo de actividad
  v_dur := greatest(1, ((t_end - t_start) / 1000)::int);
  max_speed := case ch.activity_type when 'run' then 8.5
                                     when 'bike' then 25 else 4 end;
  if cum / v_dur > max_speed then
    raise exception 'La velocidad registrada no es plausible para esta actividad';
  end if;

  -- 5) Se registra el resultado
  select min(x.duration_seconds) into prev_best
  from public.challenge_results x
  where x.challenge_id = p_challenge_id and x.user_id = me;

  insert into public.challenge_results
    (challenge_id, user_id, activity_id, duration_seconds, completed_at)
  values (p_challenge_id, me, p_activity_id, v_dur, to_timestamp(t_end / 1000.0));

  v_my_best := least(coalesce(prev_best, v_dur), v_dur);
  select count(*) + 1 into v_pos from (
    select x.user_id, min(x.duration_seconds) as m
    from public.challenge_results x
    where x.challenge_id = p_challenge_id
    group by x.user_id
  ) t where t.m < v_my_best;
  select count(distinct x.user_id) into v_total
  from public.challenge_results x where x.challenge_id = p_challenge_id;

  return jsonb_build_object(
    'duration_seconds', v_dur,
    'position', v_pos,
    'participants', v_total,
    'personal_best', prev_best is null or v_dur < prev_best
  );
end;
$$;

-- ===== Ranking: el mejor tiempo de cada participante =====
create function public.challenge_ranking(p_challenge_id uuid)
returns table (rank_pos integer, user_id uuid, name text,
               duration_seconds integer, completed_at timestamptz)
language sql stable security definer set search_path = ''
as $$
  with best as (
    select distinct on (r.user_id) r.user_id, r.duration_seconds, r.completed_at
    from public.challenge_results r
    where r.challenge_id = p_challenge_id
      and not public.is_blocked_between(auth.uid(), r.user_id)
    order by r.user_id, r.duration_seconds, r.completed_at
  )
  select (rank() over (order by b.duration_seconds))::int,
         b.user_id, pr.first_name || ' ' || pr.last_name,
         b.duration_seconds, b.completed_at
  from best b
  join public.profiles pr on pr.id = b.user_id
  where public.can_view_challenge(p_challenge_id, auth.uid())
  order by 1, b.completed_at
  limit 50;
$$;

-- ===== Listados y detalle, con estadísticas y recomendación =====
-- p_scope: 'recommended' | 'explore' | 'mine' | 'one' (con p_id)
create function public.get_challenges(p_scope text default 'explore',
                                      p_id uuid default null)
returns table (
  id uuid, title text, description text, activity_type text,
  distance_meters double precision, elevation_gain_meters double precision,
  visibility text, created_by uuid, creator_name text, created_at timestamptz,
  participants integer, avg_seconds double precision, best_seconds integer,
  my_best_seconds integer, my_position integer, preview jsonb, reason text)
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
  vis as (
    select c.* from public.challenges c
    where c.status = 'active'
      and (p_id is null or c.id = p_id)
      and public.can_view_challenge(c.id, auth.uid())
  ),
  best as (
    select distinct on (r.challenge_id, r.user_id)
           r.challenge_id, r.user_id, r.duration_seconds, r.completed_at
    from public.challenge_results r
    where r.challenge_id in (select v.id from vis v)
      and not public.is_blocked_between(auth.uid(), r.user_id)
    order by r.challenge_id, r.user_id, r.duration_seconds, r.completed_at
  ),
  ranked as (
    select b.*, rank() over (partition by b.challenge_id
                             order by b.duration_seconds) as pos
    from best b
  ),
  stats as (
    select b.challenge_id,
           count(*)::int as participants,
           avg(b.duration_seconds)::float8 as avg_seconds,
           min(b.duration_seconds)::int as best_seconds
    from best b group by b.challenge_id
  ),
  mine as (
    select rk.challenge_id, rk.duration_seconds as my_best, rk.pos::int as my_pos
    from ranked rk where rk.user_id = auth.uid()
  ),
  scored as (
    select v.*,
      pr.first_name || ' ' || pr.last_name as creator_name,
      coalesce(st.participants, 0) as participants,
      st.avg_seconds, st.best_seconds, mn.my_best, mn.my_pos,
      coalesce(v.activity_type = me.fav_type, false) as same_type,
      coalesce((select avg(a.distance_meters) from public.activities a
                where a.user_id = me.id and a.type = v.activity_type)
               between v.distance_meters * 0.5 and v.distance_meters * 1.5,
               false) as similar_dist,
      public.are_friends(me.id, v.created_by) as is_friend,
      coalesce(exists (select 1 from public.profiles cr
                       where cr.id = v.created_by and cr.city is not null
                         and me.city is not null
                         and lower(trim(cr.city)) = lower(trim(me.city))),
               false) as same_city
    from vis v
    join public.profiles pr on pr.id = v.created_by
    cross join me
    left join stats st on st.challenge_id = v.id
    left join mine mn on mn.challenge_id = v.id
  )
  select s.id, s.title, s.description, s.activity_type, s.distance_meters,
         s.elevation_gain_meters, s.visibility, s.created_by, s.creator_name,
         s.created_at, s.participants, s.avg_seconds, s.best_seconds,
         s.my_best, s.my_pos,
         case when p_id is not null then s.preview end,
         nullif(concat_ws(' · ',
           case when s.same_type then 'Practican lo mismo que tú' end,
           case when s.similar_dist then 'Distancia parecida a la tuya' end,
           case when s.is_friend then 'De un amigo' end,
           case when s.same_city then 'De tu ciudad' end), '')
  from scored s
  where case p_scope
          when 'recommended' then s.created_by <> auth.uid() and s.my_best is null
          when 'mine' then s.created_by = auth.uid() or s.my_best is not null
          else true
        end
  order by
    case when p_scope = 'recommended' then
      (s.same_type::int * 3 + s.similar_dist::int * 2 + s.is_friend::int * 2
       + s.same_city::int + (s.participants >= 3)::int) end desc nulls last,
    case when p_scope = 'explore' then s.participants end desc nulls last,
    s.created_at desc
  limit 50;
$$;

-- ===== EXECUTE (capa 3) =====
revoke all on function public.route_preview(jsonb, int) from public, anon;
revoke all on function public.can_view_challenge(uuid, uuid) from public, anon;
revoke all on function public.create_challenge(uuid, text, text, text) from public, anon;
revoke all on function public.delete_challenge(uuid) from public, anon;
revoke all on function public.submit_challenge_attempt(uuid, uuid) from public, anon;
revoke all on function public.challenge_ranking(uuid) from public, anon;
revoke all on function public.get_challenges(text, uuid) from public, anon;

grant execute on function public.route_preview(jsonb, int) to authenticated;
grant execute on function public.can_view_challenge(uuid, uuid) to authenticated;
grant execute on function public.create_challenge(uuid, text, text, text) to authenticated;
grant execute on function public.delete_challenge(uuid) to authenticated;
grant execute on function public.submit_challenge_attempt(uuid, uuid) to authenticated;
grant execute on function public.challenge_ranking(uuid) to authenticated;
grant execute on function public.get_challenges(text, uuid) to authenticated;