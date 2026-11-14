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
-- 3. Cierres de caja
-- ---------------------------------------------------------------
-- Uno por día y turno. Lo que se carga:
--   fondo_inicial    efectivo con el que abrió la caja
--   ventas_efectivo  ventas en efectivo según el cierre (Z) de Ágora
--   ventas_tarjeta   ventas con tarjeta según el cierre (Z) de Ágora
--   efectivo_contado lo que se contó en la caja al cerrar (incluye el fondo)
--   tarjeta_datafono total del cierre del datáfono
--   pagos_efectivo   lo que se pagó con plata de la caja (proveedores, compras…)
--   retiro           lo que se saca de la caja y se guarda / va al banco
-- La página calcula:
--   efectivo esperado = fondo + ventas efectivo − pagos
--   diferencia        = contado − esperado          (0 = cuadra)
--   queda en caja     = contado − retiro            (fondo del día siguiente)
create table if not exists public.caja_cierres (
  id               bigint generated always as identity primary key,
  fecha            date not null,
  turno            text not null default 'dia' check (turno in ('dia', 'mediodia', 'noche')),
  responsable      text not null check (char_length(responsable) between 2 and 60),
  fondo_inicial    numeric(10,2) not null default 0 check (fondo_inicial >= 0),
  ventas_efectivo  numeric(10,2) not null default 0 check (ventas_efectivo >= 0),
  ventas_tarjeta   numeric(10,2) not null default 0 check (ventas_tarjeta >= 0),
  efectivo_contado numeric(10,2) not null default 0 check (efectivo_contado >= 0),
  tarjeta_datafono numeric(10,2) not null default 0 check (tarjeta_datafono >= 0),
  pagos_efectivo   numeric(10,2) not null default 0 check (pagos_efectivo >= 0),
  pagos_detalle    text check (pagos_detalle is null or char_length(pagos_detalle) <= 500),
  retiro           numeric(10,2) not null default 0 check (retiro >= 0),
  desglose         jsonb,           -- cuántos billetes y monedas de cada uno (si se contó con la ayuda)
  nota             text check (nota is null or char_length(nota) <= 1000),
  creado           timestamptz not null default now(),
  creado_por       text,
  actualizado      timestamptz not null default now(),
  actualizado_por  text,
  unique (fecha, turno)
);

-- Nadie lee la tabla directo (ni caja ni admin): todo por las funciones de abajo.
alter table public.caja_cierres enable row level security;
revoke all on public.caja_cierres from anon, authenticated;

create or replace function public._chq_num(p jsonb, k text)
returns numeric language sql immutable as $$
  select round(greatest(coalesce(nullif(regexp_replace(replace(coalesce(p ->> k, ''), ',', '.'), '[^0-9.]', '', 'g'), '')::numeric, 0), 0), 2);
$$;

create or replace function public.chequeos_cierre_json(c public.caja_cierres)
returns jsonb language sql stable as $$
  select to_jsonb(c) || jsonb_build_object(
    'esperado',   c.fondo_inicial + c.ventas_efectivo - c.pagos_efectivo,
    'dif_efectivo', c.efectivo_contado - (c.fondo_inicial + c.ventas_efectivo - c.pagos_efectivo),
    'dif_tarjeta',  c.tarjeta_datafono - c.ventas_tarjeta,
    'queda',      c.efectivo_contado - c.retiro);
$$;

-- Guardar (nuevo o corregir). Caja puede cargar y corregir hoy y los 2 días
-- anteriores; admin cualquier día.
create or replace function public.chequeos_guardar_cierre(p jsonb)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  hoy    date := (now() at time zone 'Europe/Madrid')::date;
  quien  text := auth.jwt() ->> 'email';
  v_fec  date;
  v_tur  text := coalesce(nullif(p ->> 'turno', ''), 'dia');
  v_resp text := left(btrim(coalesce(p ->> 'responsable', '')), 60);
  c      public.caja_cierres;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  begin v_fec := (p ->> 'fecha')::date; exception when others then v_fec := null; end;
  if v_fec is null or v_fec > hoy then raise exception 'Fecha no válida' using errcode = '22023'; end if;
  if not public.premios_es_admin() and v_fec < hoy - 2 then
    raise exception 'Solo se pueden cargar o corregir cierres de los últimos 3 días' using errcode = '22023';
  end if;
  if v_tur not in ('dia', 'mediodia', 'noche') then raise exception 'Turno no válido' using errcode = '22023'; end if;
  if char_length(v_resp) < 2 then raise exception 'Falta quién hizo el cierre' using errcode = '22023'; end if;

  insert into caja_cierres as k (fecha, turno, responsable, fondo_inicial, ventas_efectivo, ventas_tarjeta,
      efectivo_contado, tarjeta_datafono, pagos_efectivo, pagos_detalle, retiro, desglose, nota, creado_por, actualizado_por)
  values (v_fec, v_tur, v_resp, _chq_num(p, 'fondo_inicial'), _chq_num(p, 'ventas_efectivo'), _chq_num(p, 'ventas_tarjeta'),
      _chq_num(p, 'efectivo_contado'), _chq_num(p, 'tarjeta_datafono'), _chq_num(p, 'pagos_efectivo'),
      nullif(left(btrim(coalesce(p ->> 'pagos_detalle', '')), 500), ''), _chq_num(p, 'retiro'),
      case when jsonb_typeof(p -> 'desglose') = 'object' then p -> 'desglose' end,
      nullif(left(btrim(coalesce(p ->> 'nota', '')), 1000), ''), quien, quien)
  on conflict (fecha, turno) do update set
      responsable = excluded.responsable, fondo_inicial = excluded.fondo_inicial,
      ventas_efectivo = excluded.ventas_efectivo, ventas_tarjeta = excluded.ventas_tarjeta,
      efectivo_contado = excluded.efectivo_contado, tarjeta_datafono = excluded.tarjeta_datafono,
      pagos_efectivo = excluded.pagos_efectivo, pagos_detalle = excluded.pagos_detalle,
      retiro = excluded.retiro, desglose = excluded.desglose, nota = excluded.nota,
      actualizado = now(), actualizado_por = quien
  returning * into c;
  return public.chequeos_cierre_json(c);
end $$;

-- Lista de cierres (los últimos p_dias días) + el fondo con que debería abrir hoy
create or replace function public.chequeos_cierres(p_dias int default 60)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  hoy date := (now() at time zone 'Europe/Madrid')::date;
  ult public.caja_cierres;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  select * into ult from caja_cierres where fecha < hoy or (fecha = hoy and turno = 'mediodia')
   order by fecha desc, case turno when 'noche' then 3 when 'dia' then 2 else 1 end desc limit 1;
  return jsonb_build_object(
    'cierres', coalesce((select jsonb_agg(public.chequeos_cierre_json(c) order by c.fecha desc,
                  case c.turno when 'noche' then 3 when 'dia' then 2 else 1 end desc)
                from caja_cierres c where c.fecha >= hoy - least(greatest(coalesce(p_dias, 60), 1), 400)), '[]'::jsonb),
    'ultimo', case when ult.id is not null then public.chequeos_cierre_json(ult) end,
    'admin', public.premios_es_admin());
end $$;

-- Borrar un cierre cargado por error: solo admin
create or replace function public.chequeos_borrar_cierre(p_id bigint)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.premios_es_admin() then raise exception 'Sin permiso'; end if;
  delete from caja_cierres where id = p_id;
  return jsonb_build_object('estado', case when found then 'ok' else 'no_existe' end);
end $$;

revoke execute on function public.chequeos_ruleta()                   from public;
revoke execute on function public.chequeos_reservas(int)              from public;
revoke execute on function public.chequeos_guardar_cierre(jsonb)      from public;
revoke execute on function public.chequeos_cierres(int)               from public;
revoke execute on function public.chequeos_borrar_cierre(bigint)      from public;
revoke execute on function public.chequeos_cierre_json(public.caja_cierres) from public, anon, authenticated;
grant  execute on function public.chequeos_ruleta()                   to authenticated;
grant  execute on function public.chequeos_reservas(int)              to authenticated;
grant  execute on function public.chequeos_guardar_cierre(jsonb)      to authenticated;
grant  execute on function public.chequeos_cierres(int)               to authenticated;
grant  execute on function public.chequeos_borrar_cierre(bigint)      to authenticated;
