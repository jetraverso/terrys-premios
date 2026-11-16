-- Terry's Chequeos — la página del local para el día a día (chequeos.html)
-- Pegá TODO este archivo en Supabase → SQL Editor → Run, DESPUÉS de schema.sql
-- (usa la lista premios_staff) y en el mismo proyecto que Administración
-- (lee la tabla reservas). Se puede correr las veces que haga falta: no borra datos.
--
-- Entra cualquiera de premios_staff (rol 'caja' o 'admin'). El usuario de caja
-- NO lee ninguna tabla directo: solo llama a estas funciones, que le devuelven
-- lo justo. Para sumar otro chequeo más adelante: otra función chequeos_… y
-- otra solapa en chequeos.html.

-- ---------------------------------------------------------------
-- 1. Ruleta: cómo viene el día
-- ---------------------------------------------------------------
create or replace function public.chequeos_ruleta()
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  hoy date := (now() at time zone 'Europe/Madrid')::date;
  r   jsonb;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  select jsonb_build_object(
    'jugadas_hoy',   count(*) filter (where (creado at time zone 'Europe/Madrid')::date = hoy),
    'premios_hoy',   count(codigo) filter (where (creado at time zone 'Europe/Madrid')::date = hoy),
    'canjeados_hoy', count(*) filter (where canjeado is not null and (canjeado at time zone 'Europe/Madrid')::date = hoy),
    'por_canjear',   count(*) filter (where codigo is not null and telefono is not null and canjeado is null and vence >= hoy),
    'vencen_7',      count(*) filter (where codigo is not null and telefono is not null and canjeado is null and vence between hoy and hoy + 7),
    'tickets_hoy',   (select count(*) from premios_pedidos where ticket is not null and (creado at time zone 'Europe/Madrid')::date = hoy))
    into r
    from premios_jugadas;
  return r || jsonb_build_object('canjes_hoy', public.premios_canjes_hoy());
end $$;

-- ---------------------------------------------------------------
-- 2. Próximas reservas (las de la web, tabla de Administración)
--    Solo mirar: confirmarlas o rechazarlas sigue siendo cosa de Administración.
-- ---------------------------------------------------------------
create or replace function public.chequeos_reservas(p_dias int default 30)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  hoy date := (now() at time zone 'Europe/Madrid')::date;
  r   jsonb;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  if to_regclass('public.reservas') is null then return '[]'::jsonb; end if;
  execute $q$
    select coalesce(jsonb_agg(jsonb_build_object(
        'id', id, 'fecha', fecha, 'hora', to_char(hora, 'HH24:MI'), 'personas', personas,
        'nombre', nombre, 'telefono', telefono, 'comentario', comentario, 'estado', estado,
        'nota', nota, 'creada', creada) order by fecha, hora, id), '[]'::jsonb)
      from public.reservas
     where fecha between $1 and $1 + $2 and estado in ('pendiente', 'confirmada')
  $q$ into r using hoy, least(greatest(coalesce(p_dias, 30), 1), 90);
  return r;
end $$;

-- ---------------------------------------------------------------
-- 3. Cierre de caja: arqueo por billetes y monedas
-- ---------------------------------------------------------------
-- Lo mismo que la planilla "HOJA CIERRE CAJA": por cada día y turno (día / noche)
-- se anota lo que hay en la caja al abrir (apertura) y al cerrar (cierre), contado
-- por billetes y monedas, y quién lo contó. Hay un arqueo por (fecha, turno,
-- estado): guardar otra vez el mismo lo corrige.
--   piezas  {"50": 11, "20": 9, "0.2": 12}  cuántos billetes / monedas de cada valor
--   total   lo calcula la base con esas piezas
create table if not exists public.caja_arqueos (
  id              bigint generated always as identity primary key,
  fecha           date not null,
  turno           text not null check (turno in ('dia', 'noche')),
  estado          text not null check (estado in ('apertura', 'cierre')),
  usuario         text not null check (char_length(usuario) between 2 and 40),
  piezas          jsonb not null default '{}'::jsonb,
  total           numeric(10,2) not null default 0 check (total >= 0),
  creado          timestamptz not null default now(),
  creado_por      text,
  actualizado     timestamptz not null default now(),
  actualizado_por text,
  unique (fecha, turno, estado)
);

-- Nadie lee la tabla directo (ni caja ni admin): todo por las funciones de abajo.
alter table public.caja_arqueos enable row level security;
revoke all on public.caja_arqueos from anon, authenticated;

-- Guardar (nuevo o corregir). Caja puede cargar y corregir hoy y los 2 días
-- anteriores; admin cualquier día.
create or replace function public.chequeos_guardar_arqueo(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  hoy   date := (now() at time zone 'Europe/Madrid')::date;
  quien text := auth.jwt() ->> 'email';
  v_fec date;
  v_tur text := coalesce(p ->> 'turno', '');
  v_est text := coalesce(p ->> 'estado', '');
  v_usu text := left(btrim(coalesce(p ->> 'usuario', '')), 40);
  v_pz  jsonb := '{}'::jsonb;
  v_tot numeric := 0;
  d     text;
  n     int;
  a     public.caja_arqueos;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  begin v_fec := (p ->> 'fecha')::date; exception when others then v_fec := null; end;
  if v_fec is null or v_fec > hoy then raise exception 'Fecha no válida' using errcode = '22023'; end if;
  if not public.premios_es_admin() and v_fec < hoy - 2 then
    raise exception 'Solo se pueden cargar o corregir arqueos de los últimos 3 días' using errcode = '22023';
  end if;
  if v_tur not in ('dia', 'noche') then raise exception 'Turno no válido' using errcode = '22023'; end if;
  if v_est not in ('apertura', 'cierre') then raise exception 'Estado no válido' using errcode = '22023'; end if;
  if char_length(v_usu) < 2 then raise exception 'Falta quién hizo el arqueo' using errcode = '22023'; end if;

  -- Solo los billetes y monedas que existen; cantidades enteras entre 0 y 9999
  foreach d in array array['200','100','50','20','10','5','2','1','0.5','0.2','0.1','0.05','0.02','0.01'] loop
    begin n := floor((p -> 'piezas' ->> d)::numeric)::int; exception when others then n := 0; end;
    n := least(greatest(coalesce(n, 0), 0), 9999);
    if n > 0 then
      v_pz  := v_pz || jsonb_build_object(d, n);
      v_tot := v_tot + n * d::numeric;
    end if;
  end loop;

  insert into caja_arqueos (fecha, turno, estado, usuario, piezas, total, creado_por, actualizado_por)
  values (v_fec, v_tur, v_est, v_usu, v_pz, v_tot, quien, quien)
  on conflict (fecha, turno, estado) do update set
      usuario = excluded.usuario, piezas = excluded.piezas, total = excluded.total,
      actualizado = now(), actualizado_por = quien
  returning * into a;
  return to_jsonb(a);
end $$;

-- Lista de arqueos (los últimos p_dias días), del más nuevo al más viejo,
-- y los nombres que ya se usaron (para los botones de "Quién")
create or replace function public.chequeos_arqueos(p_dias int default 60)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  return jsonb_build_object(
    'arqueos', coalesce((select jsonb_agg(to_jsonb(a) order by a.fecha desc,
                  (case a.turno when 'noche' then 2 else 0 end + case a.estado when 'cierre' then 1 else 0 end) desc)
                from caja_arqueos a where a.fecha >= hoy - least(greatest(coalesce(p_dias, 60), 1), 400)), '[]'::jsonb),
    'usuarios', coalesce((select jsonb_agg(u order by u) from (select distinct usuario as u from caja_arqueos where fecha >= hoy - 180) s), '[]'::jsonb),
    'admin', public.premios_es_admin());
end $$;

-- Borrar un arqueo cargado por error: solo admin
create or replace function public.chequeos_borrar_arqueo(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.premios_es_admin() then raise exception 'Sin permiso'; end if;
  delete from caja_arqueos where id = p_id;
  return jsonb_build_object('estado', case when found then 'ok' else 'no_existe' end);
end $$;

revoke execute on function public.chequeos_guardar_arqueo(jsonb) from public;
revoke execute on function public.chequeos_arqueos(int)          from public;
revoke execute on function public.chequeos_borrar_arqueo(bigint) from public;
grant  execute on function public.chequeos_guardar_arqueo(jsonb) to authenticated;
grant  execute on function public.chequeos_arqueos(int)          to authenticated;
grant  execute on function public.chequeos_borrar_arqueo(bigint) to authenticated;

-- La versión anterior del cierre (tabla caja_cierres y funciones chequeos_cierres,
-- chequeos_guardar_cierre, chequeos_borrar_cierre) ya no la usa la página. Si se
-- había instalado, queda en la base sin molestar; no se borra nada acá.

revoke execute on function public.chequeos_ruleta()      from public;
revoke execute on function public.chequeos_reservas(int) from public;
grant  execute on function public.chequeos_ruleta()      to authenticated;
grant  execute on function public.chequeos_reservas(int) to authenticated;
