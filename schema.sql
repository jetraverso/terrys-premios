-- Terry's Premios — tablas y seguridad para Supabase
-- Pegá TODO este archivo en Supabase → SQL Editor → Run.
-- Va en el mismo proyecto que Terry's Administración (usa los mismos usuarios
-- para entrar a la página del local). Todas las tablas empiezan con premios_
-- y no tocan nada de lo que ya está.
-- Se puede correr las veces que haga falta: no borra datos.

-- ---------------------------------------------------------------
-- 1. Configuración (una sola fila)
-- ---------------------------------------------------------------
create table if not exists public.premios_config (
  id                 int primary key default 1 check (id = 1),
  activo             boolean not null default true,  -- false = la ruleta se apaga
  dias_entre_jugadas int     not null default 0,     -- (ya no se usa: ahora manda el saldo de tiros)
  dias_validez       int     not null default 30,    -- cuántos días dura un premio para canjear
  max_premios_dia    int                             -- tope de premios por día (vacío = sin tope)
);
alter table public.premios_config add column if not exists max_jugadas_dia  int not null default 0;  -- tope de tiros por móvil y por día (0 = sin tope)
alter table public.premios_config add column if not exists tiros_por_pedido int not null default 3;  -- tiros que da cada ticket registrado
alter table public.premios_config add column if not exists max_pedidos_dia  int not null default 3;  -- pedidos por móvil y por día (freno a números inventados; 0 = sin tope)
alter table public.premios_config add column if not exists bono_cada_5      int not null default 3;  -- tiros extra en los pedidos 5, 15, 25…
alter table public.premios_config add column if not exists bono_cada_10     int not null default 6;  -- tiros extra en los pedidos 10, 20, 30…
alter table public.premios_config add column if not exists tiros_bienvenida int not null default 3;  -- tiros de regalo la primera vez (folleto), una vez por móvil
alter table public.premios_config add column if not exists dias_ticket      int not null default 7;  -- antigüedad máxima del ticket que se acepta (días)
alter table public.premios_config alter column max_jugadas_dia set default 0;
comment on column public.premios_config.max_jugadas_dia is 'Tope de tiros por móvil y por día (0 = sin tope)';
insert into public.premios_config (id) values (1) on conflict (id) do nothing;

-- ---------------------------------------------------------------
-- 2. Premios: qué da cada combinación de 3 iguales y con qué chance
-- ---------------------------------------------------------------
-- probabilidad = % de jugadas que salen con ese premio.
-- Lo que falte para 100 es "sin premio". Se cambia en Table Editor.
create table if not exists public.premios_catalogo (
  simbolo      text primary key,                -- nombre de la imagen en img/ (sin .webp)
  personaje    text not null default '',
  premio       text not null,
  probabilidad numeric(5,2) not null default 0 check (probabilidad between 0 and 100),
  orden        int not null default 0
);
alter table public.premios_catalogo drop constraint if exists premios_catalogo_simbolo_check;
alter table public.premios_catalogo add column if not exists personaje text not null default '';
-- Todos los símbolos de esta tabla salen en los rodillos (aunque tengan probabilidad 0).
insert into public.premios_catalogo (simbolo, personaje, premio, probabilidad, orden) values
  ('logo',    'Logo Terry''s', 'Menú Terry''s gratis',     0.2, 1),
  ('burgers', 'Los Terry''s',  'Burger Terry''s gratis',   0.3, 2),
  ('perro',   'Rumpi',    'Burger Rumpi gratis',      0.5, 3),
  ('botella', 'Buba',     'Burger Buba gratis',       0.5, 4),
  ('lata',    'Russel',   'Burger Russel gratis',     0.5, 5),
  ('bacon',   'Torch',    'Burger Torch gratis',      0.5, 6),
  ('patatas', 'Zulma',    'Burger Zulma gratis',      0.5, 7),
  ('cerveza', 'Cerveza',  'Copa de cerveza gratis',   4,   8),
  ('desc10',  '10%',      '10% de descuento',         8,   9),
  ('desc5',   '5%',       '5% de descuento',          18,  10)
on conflict (simbolo) do nothing;

-- ---------------------------------------------------------------
-- 3. Quién puede entrar a la página del local
-- ---------------------------------------------------------------
-- Tiene que tener usuario en Authentication y estar en esta lista.
--   insert into public.premios_staff (email, nombre) values ('tu@mail.com', 'Tu nombre');
create table if not exists public.premios_staff (
  email  text primary key,
  nombre text not null default '',
  creado timestamptz not null default now()
);

create or replace function public.premios_es_staff()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from public.premios_staff
    where lower(email) = lower(coalesce(auth.jwt() ->> 'email', ''))
  );
$$;

-- ---------------------------------------------------------------
-- 4. La base: jugadores y jugadas
-- ---------------------------------------------------------------
create table if not exists public.premios_jugadores (
  telefono       text primary key,            -- siempre con prefijo: +34600111222
  nombre         text not null,
  email          text,
  acepta_promos  boolean not null default false,
  origen         text,                        -- de qué QR vino la primera vez (?o=...)
  jugadas        int not null default 0,
  premios        int not null default 0,
  primera_jugada timestamptz not null default now(),
  ultima_jugada  timestamptz
);
alter table public.premios_jugadores add column if not exists pedidos    int not null default 0;  -- pedidos registrados (para los bonos)
alter table public.premios_jugadores add column if not exists tiros      int not null default 0;  -- tiros que le quedan por usar
alter table public.premios_jugadores add column if not exists token_hash text;                    -- llave del móvil que juega (md5)

create table if not exists public.premios_jugadas (
  id           bigint generated always as identity primary key,
  telefono     text not null references public.premios_jugadores (telefono) on update cascade on delete cascade,
  creado       timestamptz not null default now(),
  rodillos     text[] not null,
  simbolo      text,                          -- vacío = sin premio
  premio       text,
  codigo       text unique,                   -- T-XXXXX, solo si ganó
  vence        date,
  canjeado     timestamptz,
  canjeado_por text,
  origen       text,
  pedido       text,                          -- nº de pedido de Glovo: los 3 números, sin el #
  dia          date not null default ((now() at time zone 'Europe/Madrid')::date)  -- día de la jugada (hora de España)
);
alter table public.premios_jugadas add column if not exists pedido text;
alter table public.premios_jugadas add column if not exists dia date not null default ((now() at time zone 'Europe/Madrid')::date);
update public.premios_jugadas set dia = (creado at time zone 'Europe/Madrid')::date
 where dia <> (creado at time zone 'Europe/Madrid')::date;
-- Ahora un pedido da varios tiros: la regla "un número por día" vive en premios_pedidos
drop index if exists public.premios_jugadas_pedido_idx;
drop index if exists public.premios_jugadas_pedido_dia_idx;
create index if not exists premios_jugadas_ped_idx on public.premios_jugadas (pedido, dia);

-- Cada pedido de Glovo registrado. Glovo repite los números (# y 3 números),
-- así que cada número vale una vez por día.
create table if not exists public.premios_pedidos (
  id       bigint generated always as identity primary key,
  telefono text not null references public.premios_jugadores (telefono) on update cascade on delete cascade,
  pedido   text not null,
  dia      date not null default ((now() at time zone 'Europe/Madrid')::date),
  creado   timestamptz not null default now(),
  tiros    int not null default 0,          -- tiros que dio (incluido el bono)
  bono     int not null default 0,          -- de esos, cuántos fueron de bono
  unique (pedido, dia)
);
create index if not exists premios_pedidos_tel_idx on public.premios_pedidos (telefono, creado desc);
-- Tickets de compra de Ágora (número y fecha): reemplazan al # de Glovo.
-- Un ticket vale una sola vez (el número es único dentro del año).
alter table public.premios_pedidos alter column pedido drop not null;
alter table public.premios_pedidos add column if not exists ticket       int;
alter table public.premios_pedidos add column if not exists fecha_ticket date;
alter table public.premios_pedidos add column if not exists anio         int;
alter table public.premios_pedidos add column if not exists verif        text;           -- ok | pendiente | no
alter table public.premios_pedidos add column if not exists importe      numeric(10,2);  -- según Ágora
alter table public.premios_pedidos add column if not exists canal        text;           -- Glovo, Local, Take Away… según Ágora
alter table public.premios_pedidos add column if not exists verificado   timestamptz;
create unique index if not exists premios_pedidos_ticket_idx on public.premios_pedidos (ticket, anio) where ticket is not null;

-- Visitantes: el que escanea el folleto juega sin registrarse. Se lo reconoce
-- por un secreto que guarda su móvil (solo se guarda la huella).
create table if not exists public.premios_visitantes (
  id         bigint generated always as identity primary key,
  huella     text not null unique,            -- md5 del secreto del móvil
  tiros      int not null default 0,
  creado     timestamptz not null default now(),
  origen     text,
  telefono   text references public.premios_jugadores (telefono) on update cascade on delete set null,
  registrado timestamptz
);
alter table public.premios_jugadores add column if not exists bienvenida timestamptz;  -- cuándo cobró sus premios de bienvenida
alter table public.premios_jugadas alter column telefono drop not null;                 -- vacío = jugada de bienvenida sin registrarse todavía
alter table public.premios_jugadas add column if not exists visitante bigint references public.premios_visitantes (id) on delete cascade;
alter table public.premios_jugadas add column if not exists ticket    int;
alter table public.premios_jugadas add column if not exists canal     text;              -- bienvenida | ticket | pedido (Glovo, antes)

-- Los pedidos de antes (1 tiro cada uno) pasan a esta tabla, y el contador de cada jugador se recalcula
insert into public.premios_pedidos (telefono, pedido, dia, creado, tiros)
select distinct on (pedido, dia) telefono, pedido, dia, creado, 1
  from public.premios_jugadas where pedido is not null
 order by pedido, dia, creado
on conflict (pedido, dia) do nothing;
update public.premios_jugadores j set pedidos = c.n
  from (select telefono, count(*) n from public.premios_pedidos group by telefono) c
 where c.telefono = j.telefono and j.pedidos <> c.n;
create index if not exists premios_jugadas_tel_idx    on public.premios_jugadas (telefono, creado desc);
create index if not exists premios_jugadas_creado_idx on public.premios_jugadas (creado desc);

-- Nadie de afuera lee ni escribe las tablas directo: el cliente solo puede
-- llamar a las funciones de abajo, y el local solo ve si está en premios_staff.
alter table public.premios_config    enable row level security;
alter table public.premios_catalogo  enable row level security;
alter table public.premios_staff     enable row level security;
alter table public.premios_jugadores enable row level security;
alter table public.premios_jugadas   enable row level security;
alter table public.premios_pedidos   enable row level security;
alter table public.premios_visitantes enable row level security;

revoke all on public.premios_config, public.premios_catalogo, public.premios_staff,
              public.premios_jugadores, public.premios_jugadas, public.premios_pedidos, public.premios_visitantes from anon, authenticated;
grant select on public.premios_config, public.premios_catalogo,
                public.premios_jugadores, public.premios_jugadas, public.premios_pedidos to authenticated;

drop policy if exists premios_staff_lee on public.premios_config;
create policy premios_staff_lee on public.premios_config    for select to authenticated using (public.premios_es_staff());
drop policy if exists premios_staff_lee on public.premios_catalogo;
create policy premios_staff_lee on public.premios_catalogo  for select to authenticated using (public.premios_es_staff());
drop policy if exists premios_staff_lee on public.premios_jugadores;
create policy premios_staff_lee on public.premios_jugadores for select to authenticated using (public.premios_es_staff());
drop policy if exists premios_staff_lee on public.premios_jugadas;
create policy premios_staff_lee on public.premios_jugadas   for select to authenticated using (public.premios_es_staff());
drop policy if exists premios_staff_lee on public.premios_pedidos;
create policy premios_staff_lee on public.premios_pedidos   for select to authenticated using (public.premios_es_staff());

-- ---------------------------------------------------------------
-- 5. Teléfono: siempre igual escrito, así no juega dos veces
--    con "600 11 12 22" y "+34600111222"
-- ---------------------------------------------------------------
create or replace function public.premios_tel(p text)
returns text language plpgsql immutable as $$
declare d text := regexp_replace(coalesce(p, ''), '[^0-9+]', '', 'g');
begin
  if d like '00%' then d := '+' || substr(d, 3); end if;
  if d ~ '^\+34[0-9]{9}$' then return d; end if;
  if d ~ '^\+[1-9][0-9]{7,14}$' and d !~ '^\+34' then return d; end if;
  d := replace(d, '+', '');
  if d ~ '^[6789][0-9]{8}$' then return '+34' || d; end if;
  if d ~ '^34[6789][0-9]{8}$' then return '+' || d; end if;
  return null;
end $$;

-- ---------------------------------------------------------------
-- 6. Jugar, en dos pasos. Lo llama la página del QR; el resultado se decide
--    acá (en el servidor), así nadie puede hacer trampa desde el navegador.
--    a) premios_registrar_pedido: el cliente pone su pedido de Glovo y suma
--       tiros (3 por pedido + bono cada 5 pedidos). Devuelve una llave para
--       ese móvil.
--    b) premios_tirar: gasta un tiro (con la llave) y gira.
-- ---------------------------------------------------------------
create or replace function public.premios_pedido(p text)
returns text language sql immutable as $$
  select nullif(regexp_replace(coalesce(p, ''), '[^0-9]', '', 'g'), '');
$$;

-- Próximo bono: pedidos 5, 15, 25… dan bono_cada_5; 10, 20, 30… dan bono_cada_10
create or replace function public.premios_bono(n int, cfg public.premios_config)
returns int language sql immutable as $$
  select case when n > 0 and n % 10 = 0 then cfg.bono_cada_10
              when n > 0 and n % 5 = 0 then cfg.bono_cada_5 else 0 end;
$$;
create or replace function public.premios_proximo_bono(n int, cfg public.premios_config)
returns jsonb language sql immutable as $$
  select jsonb_build_object('pedidos', m, 'tiros', public.premios_bono(m, cfg))
    from (select (n / 5 + 1) * 5 as m) x;
$$;

drop function if exists public.premios_jugar(text, text, text, boolean, text);
drop function if exists public.premios_jugar(text, text, text, text, boolean, text);

create or replace function public.premios_registrar_pedido(
  p_nombre text, p_telefono text, p_pedido text, p_email text default null,
  p_promos boolean default false, p_origen text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  cfg  public.premios_config;
  tel  text := public.premios_tel(p_telefono);
  nom  text := left(btrim(regexp_replace(coalesce(p_nombre, ''), '\s+', ' ', 'g')), 60);
  mail text := nullif(lower(left(btrim(coalesce(p_email, '')), 120)), '');
  ped  text := public.premios_pedido(p_pedido);
  ori  text := nullif(left(regexp_replace(coalesce(p_origen, ''), '[^a-zA-Z0-9_-]', '', 'g'), 40), '');
  hoy  date := (now() at time zone 'Europe/Madrid')::date;
  usado public.premios_pedidos;
  jug  public.premios_jugadores;
  tok  text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  bono int;
begin
  select * into cfg from premios_config where id = 1;
  if not found or not cfg.activo then return jsonb_build_object('estado', 'cerrado'); end if;
  if length(nom) < 2 then return jsonb_build_object('estado', 'error', 'campo', 'nombre'); end if;
  if tel is null then return jsonb_build_object('estado', 'error', 'campo', 'telefono'); end if;
  if ped is null or ped !~ '^[0-9]{3}$' then return jsonb_build_object('estado', 'error', 'campo', 'pedido'); end if;
  if mail is not null and mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('estado', 'error', 'campo', 'email');
  end if;

  -- De a uno por pedido y por teléfono (dos toques rápidos no suman dos veces)
  perform pg_advisory_xact_lock(hashtext('premios:pedido:' || ped || ':' || hoy));
  perform pg_advisory_xact_lock(hashtext('premios:' || tel));

  select * into usado from premios_pedidos where pedido = ped and dia = hoy;
  if usado.id is not null then
    -- Si es la misma persona (mismo móvil y nombre), recupera sus tiros en este móvil
    select * into jug from premios_jugadores where telefono = tel;
    if usado.telefono = tel and lower(jug.nombre) = lower(nom) then
      update premios_jugadores set token_hash = md5(tok) where telefono = tel;
      return jsonb_build_object('estado', 'pedido_usado', 'propio', true, 'token', tok,
        'tiros', jug.tiros, 'pedidos', jug.pedidos, 'proximo', public.premios_proximo_bono(jug.pedidos, cfg));
    end if;
    return jsonb_build_object('estado', 'pedido_usado', 'propio', false);
  end if;

  if cfg.max_pedidos_dia > 0 and (select count(*) from premios_pedidos where telefono = tel and dia = hoy) >= cfg.max_pedidos_dia then
    return jsonb_build_object('estado', 'tope_dia');
  end if;

  insert into premios_jugadores (telefono, nombre, email, acepta_promos, origen)
  values (tel, nom, mail, coalesce(p_promos, false), ori)
  on conflict (telefono) do update
    set nombre = excluded.nombre,
        email = coalesce(excluded.email, premios_jugadores.email),
        acepta_promos = excluded.acepta_promos;

  update premios_jugadores set pedidos = pedidos + 1 where telefono = tel returning * into jug;
  bono := public.premios_bono(jug.pedidos, cfg);
  update premios_jugadores
     set tiros = tiros + cfg.tiros_por_pedido + bono, token_hash = md5(tok)
   where telefono = tel returning * into jug;
  insert into premios_pedidos (telefono, pedido, dia, tiros, bono)
  values (tel, ped, hoy, cfg.tiros_por_pedido + bono, bono);

  return jsonb_build_object('estado', 'ok', 'token', tok, 'tiros', jug.tiros, 'pedidos', jug.pedidos,
    'sumados', cfg.tiros_por_pedido, 'bono', bono, 'proximo', public.premios_proximo_bono(jug.pedidos, cfg));
end $$;

-- Saldo del móvil (al abrir la página)
create or replace function public.premios_saldo(p_telefono text, p_token text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  cfg public.premios_config;
  jug public.premios_jugadores;
begin
  select * into cfg from premios_config where id = 1;
  select * into jug from premios_jugadores where telefono = public.premios_tel(p_telefono);
  if jug.telefono is null or jug.token_hash is null or jug.token_hash <> md5(coalesce(p_token, '')) then
    return jsonb_build_object('estado', 'sesion');
  end if;
  return jsonb_build_object('estado', 'ok', 'tiros', jug.tiros, 'pedidos', jug.pedidos,
    'proximo', public.premios_proximo_bono(jug.pedidos, cfg));
end $$;

-- El sorteo en sí: elige premio según las chances, arma los rodillos y el código
create or replace function public.premios_sorteo(cfg public.premios_config)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  hoy  date := (now() at time zone 'Europe/Madrid')::date;
  c    record;
  r    numeric := random() * 100;
  acc  numeric := 0;
  sim  text;
  prem text;
  rod  text[];
  cod  text;
  vto  date;
  syms text[];
  n    int;
  alf  text := 'ACDEFGHJKLMNPQRTUVWXY34679';
begin
  select array_agg(simbolo order by orden) into syms from premios_catalogo;
  n := coalesce(array_length(syms, 1), 0);
  if n < 2 then return null; end if;

  for c in select * from premios_catalogo where probabilidad > 0 order by orden loop
    acc := acc + c.probabilidad;
    if r < acc then sim := c.simbolo; prem := c.premio; exit; end if;
  end loop;

  if sim is not null and cfg.max_premios_dia is not null and (
       select count(*) from premios_jugadas where codigo is not null and dia = hoy
     ) >= cfg.max_premios_dia then
    sim := null; prem := null;
  end if;

  if sim is not null then
    rod := array[sim, sim, sim];
    vto := hoy + cfg.dias_validez;
    loop
      cod := 'T-' || (select string_agg(substr(alf, 1 + floor(random() * length(alf))::int, 1), '')
                      from generate_series(1, 5));
      exit when not exists (select 1 from premios_jugadas where codigo = cod);
    end loop;
  else
    rod := array[syms[1 + floor(random() * n)::int], syms[1 + floor(random() * n)::int], syms[1 + floor(random() * n)::int]];
    if rod[1] = rod[2] and rod[2] = rod[3] then
      rod[3] := syms[1 + array_position(syms, rod[3]) % n];
    end if;
  end if;
  return jsonb_build_object('simbolo', sim, 'premio', prem, 'rodillos', to_jsonb(rod), 'codigo', cod, 'vence', vto);
end $$;

-- Tirar, para el que ya está registrado (gasta un tiro de su saldo)
create or replace function public.premios_tirar(p_telefono text, p_token text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  cfg  public.premios_config;
  tel  text := public.premios_tel(p_telefono);
  hoy  date := (now() at time zone 'Europe/Madrid')::date;
  jug  public.premios_jugadores;
  ped  public.premios_pedidos;
  s    jsonb;
begin
  select * into cfg from premios_config where id = 1;
  if not found or not cfg.activo then return jsonb_build_object('estado', 'cerrado'); end if;
  if tel is null then return jsonb_build_object('estado', 'sesion'); end if;

  perform pg_advisory_xact_lock(hashtext('premios:' || tel));
  select * into jug from premios_jugadores where telefono = tel;
  if jug.telefono is null or jug.token_hash is null or jug.token_hash <> md5(coalesce(p_token, '')) then
    return jsonb_build_object('estado', 'sesion');
  end if;
  if jug.tiros <= 0 then
    return jsonb_build_object('estado', 'sin_tiros', 'pedidos', jug.pedidos, 'proximo', public.premios_proximo_bono(jug.pedidos, cfg));
  end if;
  if cfg.max_jugadas_dia > 0 and (select count(*) from premios_jugadas where telefono = tel and dia = hoy) >= cfg.max_jugadas_dia then
    return jsonb_build_object('estado', 'tope_dia');
  end if;

  s := public.premios_sorteo(cfg);
  if s is null then return jsonb_build_object('estado', 'cerrado'); end if;

  -- La jugada queda asociada al último ticket (o pedido de Glovo) registrado
  select * into ped from premios_pedidos where telefono = tel order by creado desc limit 1;
  insert into premios_jugadas (telefono, rodillos, simbolo, premio, codigo, vence, origen, pedido, ticket, canal, dia)
  values (tel, array(select jsonb_array_elements_text(s->'rodillos')), s->>'simbolo', s->>'premio', s->>'codigo',
          (s->>'vence')::date, jug.origen, ped.pedido, ped.ticket,
          case when ped.ticket is not null then 'ticket' when ped.pedido is not null then 'pedido' else 'bienvenida' end, hoy);

  update premios_jugadores
     set tiros = tiros - 1,
         jugadas = jugadas + 1,
         premios = premios + (s->>'simbolo' is not null)::int,
         ultima_jugada = now()
   where telefono = tel returning * into jug;

  return s || jsonb_build_object('estado', 'ok', 'tiros', jug.tiros, 'pedidos', jug.pedidos,
    'proximo', public.premios_proximo_bono(jug.pedidos, cfg));
end $$;

-- ---------------------------------------------------------------
-- 6b. Bienvenida (folleto): se juega primero y se registra después
--     a) premios_visita: el móvil pide sus tiros de regalo (una vez por móvil)
--     b) premios_tirar_visita: gira sin registrarse. Si gana, el código NO se
--        le muestra hasta que se registre.
--     c) premios_registrarse: deja nombre y móvil; recibe sus premios (una
--        sola vez por número de teléfono), los tiros que le quedaban y su llave.
-- ---------------------------------------------------------------
create or replace function public.premios_visita(p_secreto text, p_origen text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  cfg public.premios_config;
  v   public.premios_visitantes;
  ori text := nullif(left(regexp_replace(coalesce(p_origen, ''), '[^a-zA-Z0-9_-]', '', 'g'), 40), '');
begin
  select * into cfg from premios_config where id = 1;
  if not found or not cfg.activo then return jsonb_build_object('estado', 'cerrado'); end if;
  if length(coalesce(p_secreto, '')) not between 20 and 100 then return jsonb_build_object('estado', 'error'); end if;
  insert into premios_visitantes (huella, tiros, origen) values (md5(p_secreto), cfg.tiros_bienvenida, ori)
  on conflict (huella) do nothing;
  select * into v from premios_visitantes where huella = md5(p_secreto);
  return jsonb_build_object('estado', 'ok', 'tiros', v.tiros, 'registrado', v.telefono is not null,
    'pendientes', (select count(*) from premios_jugadas where visitante = v.id and telefono is null and codigo is not null));
end $$;

create or replace function public.premios_tirar_visita(p_secreto text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  cfg public.premios_config;
  v   public.premios_visitantes;
  hoy date := (now() at time zone 'Europe/Madrid')::date;
  s   jsonb;
begin
  select * into cfg from premios_config where id = 1;
  if not found or not cfg.activo then return jsonb_build_object('estado', 'cerrado'); end if;
  select * into v from premios_visitantes where huella = md5(coalesce(p_secreto, '')) for update;
  if v.id is null then return jsonb_build_object('estado', 'sesion'); end if;
  if v.telefono is not null then return jsonb_build_object('estado', 'registrado'); end if;
  if v.tiros <= 0 then return jsonb_build_object('estado', 'sin_tiros'); end if;

  s := public.premios_sorteo(cfg);
  if s is null then return jsonb_build_object('estado', 'cerrado'); end if;
  insert into premios_jugadas (telefono, visitante, rodillos, simbolo, premio, codigo, vence, origen, canal, dia)
  values (null, v.id, array(select jsonb_array_elements_text(s->'rodillos')), s->>'simbolo', s->>'premio', s->>'codigo',
          (s->>'vence')::date, v.origen, 'bienvenida', hoy);
  update premios_visitantes set tiros = tiros - 1 where id = v.id returning * into v;

  -- El código queda guardado pero no se muestra: se entrega al registrarse
  return (s - 'codigo') || jsonb_build_object('estado', 'ok', 'tiros', v.tiros, 'oculto', s->>'codigo' is not null);
end $$;

create or replace function public.premios_registrarse(
  p_secreto text, p_nombre text, p_telefono text, p_email text default null,
  p_promos boolean default false, p_origen text default null)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  cfg  public.premios_config;
  v    public.premios_visitantes;
  jug  public.premios_jugadores;
  tel  text := public.premios_tel(p_telefono);
  nom  text := left(btrim(regexp_replace(coalesce(p_nombre, ''), '\s+', ' ', 'g')), 60);
  mail text := nullif(lower(left(btrim(coalesce(p_email, '')), 120)), '');
  ori  text := nullif(left(regexp_replace(coalesce(p_origen, ''), '[^a-zA-Z0-9_-]', '', 'g'), 40), '');
  tok  text := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  existia boolean;
  estado  text := 'ok';
  n int := 0; g int := 0;
  prem jsonb := '[]'::jsonb;
begin
  select * into cfg from premios_config where id = 1;
  if not found or not cfg.activo then return jsonb_build_object('estado', 'cerrado'); end if;
  if length(nom) < 2 then return jsonb_build_object('estado', 'error', 'campo', 'nombre'); end if;
  if tel is null then return jsonb_build_object('estado', 'error', 'campo', 'telefono'); end if;
  if mail is not null and mail !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('estado', 'error', 'campo', 'email');
  end if;

  perform pg_advisory_xact_lock(hashtext('premios:' || tel));
  select * into v from premios_visitantes where huella = md5(coalesce(p_secreto, '')) for update;

  -- Un móvil ya registrado con otro nombre: no se le entrega la cuenta a cualquiera que sepa el número
  select * into jug from premios_jugadores where telefono = tel;
  existia := jug.telefono is not null;
  if existia and lower(jug.nombre) <> lower(nom) then
    return jsonb_build_object('estado', 'nombre_no_coincide');
  end if;

  insert into premios_jugadores (telefono, nombre, email, acepta_promos, origen)
  values (tel, nom, mail, coalesce(p_promos, false), coalesce(ori, v.origen))
  on conflict (telefono) do update
    set nombre = premios_jugadores.nombre,   -- si ya existía, se queda con su nombre
        email = coalesce(excluded.email, premios_jugadores.email),
        acepta_promos = excluded.acepta_promos;
  select * into jug from premios_jugadores where telefono = tel;

  -- Lo jugado en este móvil antes de registrarse
  if v.id is not null and v.telefono is null then
    if jug.bienvenida is null then
      update premios_jugadas set telefono = tel where visitante = v.id and telefono is null;
      select count(*), count(codigo) into n, g from premios_jugadas where visitante = v.id;
      update premios_jugadores
         set bienvenida = now(), jugadas = jugadas + n, premios = premios + g,
             tiros = tiros + v.tiros, primera_jugada = least(primera_jugada, v.creado)
       where telefono = tel returning * into jug;
      select coalesce(jsonb_agg(jsonb_build_object('codigo', codigo, 'premio', premio, 'simbolo', simbolo, 'vence', vence) order by creado), '[]')
        into prem from premios_jugadas where visitante = v.id and codigo is not null;
    else
      -- Este número ya cobró su bienvenida en otro móvil: lo de acá no cuenta
      estado := 'bienvenida_usada';
      delete from premios_jugadas where visitante = v.id and telefono is null;
    end if;
    update premios_visitantes set telefono = tel, registrado = now(), tiros = 0 where id = v.id;
  end if;

  update premios_jugadores set token_hash = md5(tok) where telefono = tel returning * into jug;
  return jsonb_build_object('estado', estado, 'token', tok, 'nuevo', not existia,
    'tiros', jug.tiros, 'pedidos', jug.pedidos, 'proximo', public.premios_proximo_bono(jug.pedidos, cfg),
    'premios', prem);
end $$;

-- ---------------------------------------------------------------
-- 6c. Tickets de compra (Ágora): número y fecha. Cada ticket suma tiros.
--     Se comparan con las ventas que Ágora sube cada noche (ventas_dias, de
--     Terry's Administración, en este mismo proyecto).
-- ---------------------------------------------------------------
-- ok: está en Ágora ese día · no: ese día ya está cargado y el ticket no aparece
-- no_creible: el día todavía no se cargó y el número no encaja con los anteriores
-- pendiente: el día todavía no se cargó y el número es creíble (se verifica después)
create or replace function public.premios_agora_ticket(p_num int, p_fecha date)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  inv   jsonb;
  hay   boolean;
  dprev date;
  mprev int;
begin
  if to_regclass('public.ventas_dias') is null then return jsonb_build_object('estado', 'pendiente'); end if;
  execute $q$
    select i from public.ventas_dias v, jsonb_array_elements(v.bruto -> 'Invoices') i
     where v.origen = 'agora' and v.dia between $2 - 1 and $2
       and (i ->> 'Number') = $1::text
       and (left(i ->> 'Date', 10)::date = $2 or (i ->> 'BusinessDay')::date = $2)
     limit 1 $q$ into inv using p_num, p_fecha;
  if inv is not null then
    return jsonb_build_object('estado', 'ok',
      'importe', (inv -> 'Totals' ->> 'GrossAmount')::numeric,
      'canal', case when exists (select 1 from jsonb_array_elements(inv -> 'Payments') pg where pg ->> 'MethodName' ilike '%glovo%') then 'Glovo'
                    else initcap(coalesce(inv -> 'InvoiceItems' -> 0 -> 'SaleCenter' ->> 'Name', '')) end);
  end if;
  execute $q$ select exists (select 1 from public.ventas_dias where origen = 'agora' and dia = $1) $q$ into hay using p_fecha;
  if hay then return jsonb_build_object('estado', 'no'); end if;
  -- El día todavía no está: el número tiene que ser posterior al último ticket conocido y no disparatado
  execute $q$
    select v.dia, max((i ->> 'Number')::int) from public.ventas_dias v, jsonb_array_elements(v.bruto -> 'Invoices') i
     where v.origen = 'agora' and v.dia = (select max(dia) from public.ventas_dias where origen = 'agora' and dia < $1)
     group by v.dia $q$ into dprev, mprev using p_fecha;
  if mprev is null then return jsonb_build_object('estado', 'pendiente'); end if;
  if p_num <= mprev or p_num > mprev + 150 * (p_fecha - dprev) + 150 then
    return jsonb_build_object('estado', 'no_creible');
  end if;
  return jsonb_build_object('estado', 'pendiente');
end $$;

create or replace function public.premios_registrar_ticket(p_telefono text, p_token text, p_ticket text, p_fecha date)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  cfg  public.premios_config;
  tel  text := public.premios_tel(p_telefono);
  hoy  date := (now() at time zone 'Europe/Madrid')::date;
  num  int;
  jug  public.premios_jugadores;
  usado public.premios_pedidos;
  ag   jsonb;
  bono int;
begin
  select * into cfg from premios_config where id = 1;
  if not found or not cfg.activo then return jsonb_build_object('estado', 'cerrado'); end if;
  if tel is null then return jsonb_build_object('estado', 'sesion'); end if;
  if coalesce(regexp_replace(p_ticket, '[^0-9]', '', 'g'), '') !~ '^[0-9]{1,8}$' then
    return jsonb_build_object('estado', 'error', 'campo', 'ticket');
  end if;
  num := regexp_replace(p_ticket, '[^0-9]', '', 'g')::int;
  if p_fecha is null or p_fecha > hoy or p_fecha < hoy - cfg.dias_ticket then
    return jsonb_build_object('estado', 'error', 'campo', 'fecha', 'dias', cfg.dias_ticket);
  end if;

  perform pg_advisory_xact_lock(hashtext('premios:ticket:' || num));
  perform pg_advisory_xact_lock(hashtext('premios:' || tel));
  select * into jug from premios_jugadores where telefono = tel;
  if jug.telefono is null or jug.token_hash is null or jug.token_hash <> md5(coalesce(p_token, '')) then
    return jsonb_build_object('estado', 'sesion');
  end if;

  select * into usado from premios_pedidos where ticket = num and anio = extract(year from p_fecha)::int;
  if usado.id is not null then
    return jsonb_build_object('estado', 'ticket_usado', 'propio', usado.telefono = tel,
      'tiros', jug.tiros, 'pedidos', jug.pedidos, 'proximo', public.premios_proximo_bono(jug.pedidos, cfg));
  end if;
  if cfg.max_pedidos_dia > 0 and (select count(*) from premios_pedidos where telefono = tel and dia = hoy) >= cfg.max_pedidos_dia then
    return jsonb_build_object('estado', 'tope_dia');
  end if;

  ag := public.premios_agora_ticket(num, p_fecha);
  if ag ->> 'estado' in ('no', 'no_creible') then
    return jsonb_build_object('estado', 'ticket_no_coincide');
  end if;

  update premios_jugadores set pedidos = pedidos + 1 where telefono = tel returning * into jug;
  bono := public.premios_bono(jug.pedidos, cfg);
  update premios_jugadores set tiros = tiros + cfg.tiros_por_pedido + bono where telefono = tel returning * into jug;
  insert into premios_pedidos (telefono, ticket, fecha_ticket, anio, dia, tiros, bono, verif, importe, canal, verificado)
  values (tel, num, p_fecha, extract(year from p_fecha)::int, hoy, cfg.tiros_por_pedido + bono, bono,
          case when ag ->> 'estado' = 'ok' then 'ok' else 'pendiente' end,
          (ag ->> 'importe')::numeric, ag ->> 'canal', case when ag ->> 'estado' = 'ok' then now() end);

  return jsonb_build_object('estado', 'ok', 'tiros', jug.tiros, 'pedidos', jug.pedidos,
    'sumados', cfg.tiros_por_pedido, 'bono', bono, 'proximo', public.premios_proximo_bono(jug.pedidos, cfg));
end $$;

-- Caja: vuelve a mirar en Ágora los tickets que quedaron pendientes
create or replace function public.premios_verificar_tickets()
returns int language plpgsql volatile security definer set search_path = public as $$
declare
  p  record;
  ag jsonb;
  n  int := 0;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  for p in select id, ticket, fecha_ticket from premios_pedidos where ticket is not null and verif = 'pendiente' loop
    ag := public.premios_agora_ticket(p.ticket, p.fecha_ticket);
    if ag ->> 'estado' in ('ok', 'no') then
      update premios_pedidos
         set verif = ag ->> 'estado', importe = (ag ->> 'importe')::numeric, canal = ag ->> 'canal', verificado = now()
       where id = p.id;
      n := n + 1;
    end if;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------
-- 7. Canjear un código en el local
-- ---------------------------------------------------------------
create or replace function public.premios_codigo(p text)
returns text language sql immutable as $$
  select case
    when x ~ '^[A-Z0-9]{5}$' then 'T-' || x
    when x ~ '^T[A-Z0-9]{5}$' then 'T-' || substr(x, 2)
    else null end
  from (select regexp_replace(upper(coalesce(p, '')), '[^A-Z0-9]', '', 'g') as x) s;
$$;

create or replace function public.premios_canjear(p_codigo text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  j public.premios_jugadas;
  hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  select * into j from premios_jugadas where codigo = public.premios_codigo(p_codigo) for update;
  if j.id is null then return jsonb_build_object('estado', 'no_existe'); end if;
  if j.canjeado is not null then
    return jsonb_build_object('estado', 'ya_canjeado', 'canjeado', j.canjeado, 'por', j.canjeado_por);
  end if;
  if j.vence < hoy then return jsonb_build_object('estado', 'vencido', 'vence', j.vence); end if;
  update premios_jugadas set canjeado = now(), canjeado_por = auth.jwt() ->> 'email' where id = j.id;
  return jsonb_build_object('estado', 'ok');
end $$;

-- Deshacer un canje hecho por error (solo el mismo día)
create or replace function public.premios_deshacer_canje(p_codigo text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  update premios_jugadas set canjeado = null, canjeado_por = null
   where codigo = public.premios_codigo(p_codigo) and canjeado > now() - interval '12 hours';
  return jsonb_build_object('estado', case when found then 'ok' else 'no' end);
end $$;

-- ---------------------------------------------------------------
-- 8. Estado de un premio, para el móvil del cliente: así se entera
--    de que ya lo canjeó (o de que venció). Solo responde si coinciden
--    el código y el móvil del ganador.
-- ---------------------------------------------------------------
create or replace function public.premios_estado(p_codigo text, p_telefono text)
returns jsonb language plpgsql stable security definer set search_path = public as $$
declare
  j   public.premios_jugadas;
  hoy date := (now() at time zone 'Europe/Madrid')::date;
begin
  select * into j from premios_jugadas
   where codigo = public.premios_codigo(p_codigo) and telefono = public.premios_tel(p_telefono);
  if j.id is null then return jsonb_build_object('estado', 'no_existe'); end if;
  return jsonb_build_object(
    'estado', case when j.canjeado is not null then 'canjeado' when j.vence < hoy then 'vencido' else 'pendiente' end,
    'canjeado', j.canjeado, 'vence', j.vence, 'premio', j.premio, 'simbolo', j.simbolo);
end $$;

-- ---------------------------------------------------------------
-- 9. Borrar un jugador cargado mal (desde la página del local).
--    Se borran también todas sus jugadas y premios (on delete cascade).
-- ---------------------------------------------------------------
create or replace function public.premios_borrar_jugador(p_telefono text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare
  tel text := coalesce(public.premios_tel(p_telefono), p_telefono);
  n   int;
  g   int;
begin
  if not public.premios_es_staff() then raise exception 'Sin permiso'; end if;
  select count(*), count(codigo) into n, g from premios_jugadas where telefono = tel;
  delete from premios_jugadores where telefono = tel;
  if not found then return jsonb_build_object('estado', 'no_existe'); end if;
  return jsonb_build_object('estado', 'ok', 'jugadas', n, 'premios', g);
end $$;

revoke execute on function public.premios_borrar_jugador(text) from public;
grant  execute on function public.premios_borrar_jugador(text) to authenticated;

revoke execute on function public.premios_estado(text, text) from public;
grant  execute on function public.premios_estado(text, text) to anon, authenticated;

revoke execute on function public.premios_sorteo(public.premios_config) from public, anon, authenticated;
revoke execute on function public.premios_agora_ticket(int, date) from public, anon, authenticated;
revoke execute on function public.premios_visita(text, text)       from public;
revoke execute on function public.premios_tirar_visita(text)       from public;
revoke execute on function public.premios_registrarse(text, text, text, text, boolean, text) from public;
revoke execute on function public.premios_registrar_ticket(text, text, text, date) from public;
revoke execute on function public.premios_verificar_tickets()      from public;
grant  execute on function public.premios_visita(text, text)       to anon, authenticated;
grant  execute on function public.premios_tirar_visita(text)       to anon, authenticated;
grant  execute on function public.premios_registrarse(text, text, text, text, boolean, text) to anon, authenticated;
grant  execute on function public.premios_registrar_ticket(text, text, text, date) to anon, authenticated;
grant  execute on function public.premios_verificar_tickets()      to authenticated;
revoke execute on function public.premios_registrar_pedido(text, text, text, text, boolean, text) from public;
revoke execute on function public.premios_tirar(text, text)    from public;
revoke execute on function public.premios_saldo(text, text)    from public;
revoke execute on function public.premios_canjear(text)        from public;
revoke execute on function public.premios_deshacer_canje(text) from public;
grant  execute on function public.premios_registrar_pedido(text, text, text, text, boolean, text) to anon, authenticated;
grant  execute on function public.premios_tirar(text, text)    to anon, authenticated;
grant  execute on function public.premios_saldo(text, text)    to anon, authenticated;
grant  execute on function public.premios_canjear(text)        to authenticated;
grant  execute on function public.premios_deshacer_canje(text) to authenticated;
grant  execute on function public.premios_es_staff()           to authenticated;
