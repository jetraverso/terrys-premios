# Terry's Premios

La ruleta del QR de los folletos. La primera vez el cliente juega **3 tiros de regalo sin registrarse**; si gana, se registra (nombre y móvil) para ver su código. Para seguir jugando, cada **ticket de compra** (número y fecha, de Glovo, take away o el local) suma **3 tiros** (más bonos cada 5 tickets). Gira una tragaperras de 3 rodillos con los personajes de Terry's y si salen **3 iguales** gana un premio con un código (`T-K7P3Q`) para canjear **en el local**: burgers, menú, cañas o descuentos del 10 % y del 5 %. Cada jugada queda guardada en Supabase, así se va armando la base de clientes.

Publicada en GitHub Pages:

- Ruleta (a donde lleva el QR): https://ruleta.terrysburgers.com/
- Caja: https://ruleta.terrysburgers.com/local.html

El subdominio está en los DNS de GoDaddy (registro CNAME `ruleta` → `jetraverso.github.io`) y configurado como dominio propio de GitHub Pages (archivo `CNAME`). Las direcciones viejas (`jetraverso.github.io/terrys-premios/…`) redirigen solas a las nuevas, así que los QR ya impresos siguen funcionando.

Son dos páginas:

- **`index.html`** — la ruleta, a donde lleva el QR. Pensada para el móvil.
- **`local.html`** — para caja: canjear códigos, ver la base de jugadores (con CSV para Excel) y generar el QR del flyer. Pide email y contraseña.

La ruleta usa el estilo de Terry's: blanco y negro, con el logo y los personajes de los stickers. La página del local mantiene el diseño de Administración (modo noche).

## Cómo funciona

- **El resultado lo decide Supabase, no el navegador.** La página solo anima los rodillos hasta donde le dice el servidor, así nadie puede hacer trampa tocando el código de la página.
- **Primero se juega, después se registra.** Quien escanea por primera vez (folleto `?o=folleto` o flyer de la bolsa) tiene **3 tiros de regalo con premio seguro**, una vez por móvil, sin poner ningún dato: **exactamente uno** de los 3 tiros gana (cuál, al azar) y los otros dos no. El premio de bienvenida sale con su propio reparto: **2x1 en cerveza 50 %, 5 % de descuento 25 %, 10 % de descuento 20 %, una burger 5 %** (`prob_bienvenida` y `premio_bienvenida` en `premios_catalogo`). Ve qué ganó pero **el código recién aparece cuando se registra**: así ganar es lo que lo lleva a dejar sus datos. Cada número de teléfono cobra premios de bienvenida **una sola vez**: si alguien juega en otro móvil y se registra con un número que ya los cobró, lo de ese móvil no cuenta.
- **Tickets de compra:** para seguir jugando, el cliente (ya registrado) pone el **número y la fecha de su ticket** de Ágora. Cada ticket suma **3 tiros** y vale una sola vez. Se acepta hasta 7 días atrás (`dias_ticket`).
- **Verificación con Ágora:** los tickets se comparan con las ventas que Ágora sube cada noche a la base (tabla `ventas_dias` de Administración):
  - si ese día ya está cargado, el número **tiene que existir ese día**: si no, se rechaza ("no coincide con una compra de esa fecha");
  - si el día todavía no se cargó (hoy, ayer), se acepta solo si el número es **creíble**: posterior al último ticket conocido y no disparatado. Queda "pendiente" y caja lo verifica cuando Ágora sube el día;
  - en caja cada premio muestra de dónde vino: **✓ Ágora** (con importe y si fue Glovo, take away o local), **⏳ se verifica mañana**, **✗ no está en Ágora** (revisarlo antes de entregar) o **Bienvenida**.
- **Saldo de tiros por cliente (por móvil):** cada giro gasta uno y los que no usa quedan guardados. En la página ve cuántos le quedan y cuánto le falta para el próximo bono.
- **Bonos por fidelidad:** se cuentan los tickets de cada cliente. Al **5º ticket +3 tiros**, al **10º +6**, y se repite: 15º +3, 20º +6, 25º +3… (se cambia en `premios_config`).
- **La llave del móvil:** al registrarse, la base le da al móvil una llave secreta y solo con esa llave se pueden gastar sus tiros o sumar tickets. Si alguien pone el móvil de otra persona con otro nombre, se rechaza.
- **Freno a abusos:** como máximo **3 tickets por móvil y por día** (`max_pedidos_dia`). Los pedidos de Glovo con el # de 3 números (versión anterior) siguen apareciendo en caja como "#123 Glovo".
- **El móvil** se guarda siempre igual (`600 11 12 22`, `+34600111222` y `0034600111222` son la misma persona) y en ese móvil la página recuerda los datos: la próxima vez solo hay que poner el pedido nuevo.
- **Premios y chances** (se cambian en Supabase, ver abajo):

  | 3 iguales | Imagen (`img/`) | Premio | Chance por tiro |
  |---|---|---|---|
  | Logo Terry's | `logo` | Menú Terry's gratis | 0,2 % |
  | Los Terry's (las dos burgers) | `burgers` | Burger Terry's gratis | 0,3 % |
  | Rumpi (perro) | `perro` | Burger Rumpi gratis | 0,5 % |
  | Buba (botella) | `botella` | Burger Buba gratis | 0,5 % |
  | Russel | `lata` | Burger Russel gratis | 0,5 % |
  | Torch | `bacon` | Burger Torch gratis | 0,5 % |
  | Zulma | `patatas` | Burger Zulma gratis | 0,5 % |
  | Copa Estrella | `cerveza` | Copa de cerveza gratis | 4 % |
  | 10% | `desc10` | 10% de descuento | 8 % |
  | 5% | `desc5` | 5% de descuento | 18 % |
  | — | | Sin premio | 67 % |

  Con 3 tiros por pedido: de cada 100 pedidos salen más o menos 12 cañas, 9 burgers y medio menú (parecido a cuando era 1 tiro con las chances de antes), y además unos 24 descuentos del 10 % y 54 del 5 %. Unos 2 de cada 3 pedidos se llevan al menos algo. Los descuentos son para la próxima compra en el local, uno por compra (no se acumulan).
- **Varios premios a la vez:** cada premio queda guardado en el móvil. Si tiene más de uno, el aviso dice "Tienes N premios sin canjear" y al tocarlo ve la lista con todos sus códigos.
- **El premio dura 30 días** y se canjea una sola vez.
- **El cliente se entera del canje:** el premio queda guardado en su móvil, y cada vez que abre la página (o vuelve a ella) le pregunta a la base cómo está. Si ya se canjeó, el aviso pasa a "✓ Premio canjeado" y la tarjeta muestra el código tachado con un sello de CANJEADO; si venció, desaparece. Con la tarjeta abierta se vuelve a mirar cada 15 segundos, así que si la está mostrando en caja cambia sola al rato. La base solo responde si coinciden el código y el móvil del ganador (`premios_estado`).
- **Base de datos:** cada pedido registrado (`premios_pedidos`), cada tiro con su pedido (`premios_jugadas`), y por jugador: nombre, móvil, email (opcional), si acepta promociones, cuántas veces jugó y ganó, de qué QR vino (`?o=flyer`), primera y última jugada.
- **Privacidad (RGPD):** para jugar hay que aceptar la política de privacidad (tiene 14 años o más). Recibir promociones es una casilla aparte, que viene sin tildar: **solo a los que la tildan se les puede mandar publicidad**. En la página del local hay un filtro "Solo aceptan promos" para exportar esa lista.

### En caja (`local.html`)

1. El cliente muestra el código en el móvil. Se escribe en el recuadro (alcanza con las 5 letras, sin `T-`, en minúscula también) → **Buscar**.
2. Sale en verde **Válido ✓** con el premio, el nombre y el pedido de Glovo (`#482 · del 28/09/2026`): conviene mirar en Glovo que ese pedido exista ese día. Para confirmar que es él, pedile los últimos 3 números del móvil (la página los muestra).
3. **Entregar y marcar canjeado.** Si ya estaba canjeado o vencido, lo dice en gris o amarillo y no deja canjearlo.
4. Si se tocó por error, **Deshacer canje** (hasta 12 horas después).

El recuadro del código no toma el cursor solo al abrir la página ni ofrece autocompletar: solo se escribe cuando se lo toca.

También se puede canjear sin escribir el código, desde las solapas de abajo:

- **Por canjear** (con el número de pendientes): todos los premios vigentes con pedido de Glovo, cliente, premio, código y vencimiento, y un botón **Canjear** en cada uno. Se busca por pedido (`482`), nombre o código.
- **Canjeados:** el historial de lo entregado, también agrupado por día de canje: cuándo, qué pedido, a quién, qué premio y quién lo entregó (el usuario de caja). Tiene **Deshacer** durante 12 horas y se descarga en CSV.
- **Jugadas:** todas las tiradas con su pedido, resultado y estado, **agrupadas por día**: el día de hoy abierto y los anteriores plegados (se abren tocándolos), cada uno con su resumen ("3 jugadas · 2 con premio"). Al buscar o filtrar se abren solos los días que tienen resultados. Las que tienen premio pendiente también tienen botón **Canjear**.
- **Jugadores:** la base de clientes, con su **último pedido**, cuántos **pedidos** lleva y cuántos **tiros** le quedan sin usar, link a WhatsApp y CSV. Se puede buscar también por número de pedido. Cada jugador tiene a la derecha una **papelera** para eliminarlo si está mal cargado: siempre pide confirmación, avisa cuántas jugadas y premios se borran con él (incluidos los ya canjeados, que salen del historial) y no se puede deshacer.
- **QR del flyer.**

Arriba, las tarjetas con las jugadas de hoy y de la semana, jugadores, premios dados y canjeados.

## Puesta en marcha (una sola vez)

### 1. Tablas en Supabase

Va en el **mismo proyecto que Terry's Administración** (el plan gratis de Supabase permite 2 proyectos y ya están los dos usados). Todas las tablas empiezan con `premios_` y no tocan nada de Administración.

1. Supabase → proyecto de Administración → **SQL Editor** → pegá todo [`schema.sql`](schema.sql) → **Run**.
2. Quién entra a `local.html`: el usuario tiene que existir en **Authentication → Users** (el tuyo ya existe) y estar en la lista del local:
   ```sql
   insert into public.premios_staff (email, nombre) values ('tu@mail.com', 'Tu nombre');
   ```
   Para alguien de caja: primero **Authentication → Users → Add user** (email + contraseña, tildando *Auto Confirm User*) y después el mismo `insert` con su email. Estar en `premios_staff` **no** le da acceso a Administración (esa tiene su propia lista).

### 2. Datos del negocio

En `index.html`, arriba del todo en el `<script>`, completá `NEGOCIO`: **CIF**, un **email** para temas de privacidad y la **dirección del local** (salen en la tabla de premios, en el premio y en la política de privacidad).

Las dos páginas ya están conectadas al Supabase de Administración (`SUPABASE_URL` y `SUPABASE_KEY`, la clave pública). Si alguna vez las borrás, funcionan en **modo demo**: juega de mentira y guarda solo en ese navegador, y `local.html` muestra lo que se jugó en ese mismo navegador. Para probar varias veces seguidas en demo: agregá `?demo_sin_limite` a la dirección.

### 3. Publicar cambios

Repositorio: https://github.com/jetraverso/terrys-premios (GitHub Pages desde la rama `main`, carpeta raíz). Cada `git push` a `main` se publica solo en un minuto o dos.

- **Cambios en las páginas o imágenes:** se editan acá, commit y push.
- **Cambios en la base** (`schema.sql`): además del push, hay que pegar el archivo en Supabase → SQL Editor → Run. Se puede correr las veces que haga falta y no borra datos.
- **Premios, chances y configuración del día a día:** se cambian directo en Supabase → Table Editor (ver "Cambiar cosas"), sin tocar el código.

### 4. El QR

`local.html` → solapa **QR del flyer** → **Descargar SVG (imprenta)** o PNG. En **Origen** podés poner una palabra distinta por cada lugar donde lo repartas (`flyer`, `glovo`, `mesa`…) y en la lista de jugadores se ve de dónde vino cada uno. Probá el QR impreso con un par de móviles antes de mandar a imprimir todos.

### 5. Flyer de las bolsas

En [`flyer/`](flyer/) hay dos, en A6:

- **Folleto para repartir** (`terrys-folleto-A6.pdf` / `.png`): "3 tiros gratis, sin registrarte". QR a `ruleta.terrysburgers.com/?o=folleto`.
- **Flyer de las bolsas** (`terrys-flyer-A6.pdf` / `.png`): "Pon tu ticket, número y fecha". QR a `ruleta.terrysburgers.com/?o=flyer`.

Cada uno: el PDF para imprenta (A6, 10,5 × 14,8 cm, sin sangrado: los bordes son blancos) y **`terrys-flyer-A6.png`** (300 ppp) para mandar por WhatsApp o redes. El QR va a `ruleta.terrysburgers.com/?o=flyer`, así en caja se ve quién vino por el flyer.

Para cambiarlos: se edita `flyer/folleto.html` o `flyer/flyer.html` (abriéndolo en el navegador se ve la hoja en grande) y se corre `flyer/exportar.sh`, que vuelve a generar el PDF y el PNG con Chrome. Antes de imprimir muchos, probá el QR impreso con un par de móviles.

## Cambiar cosas

Todo en Supabase → **Table Editor**:

- **Premio seguro de bienvenida** (`premios_catalogo`): `prob_bienvenida` reparte el premio de la primera vez entre los símbolos (que sumen 100; con 0 no sale) y `premio_bienvenida` le cambia el nombre solo en ese caso (por ejemplo la cerveza: "2x1 en cerveza" en vez de "Copa de cerveza gratis"). Si cambiás el nombre, cambialo también en `PREMIOS` de `index.html` (`premioB`).

- **`premios_catalogo`** — un renglón por personaje: `simbolo` (el nombre de su imagen en `img/`), `premio` y `probabilidad` (en %). Lo que falte para 100 es "sin premio". Con probabilidad 0 sigue saliendo en los rodillos pero nunca da premio. *Si cambiás un premio o agregás un personaje, cambialo también en la lista `PREMIOS` de `index.html` (es lo que muestra la página); un personaje nuevo necesita su imagen en `img/` (cuadrada, fondo transparente, `.webp`).*
- **`premios_config`**:
  - `activo` — `false` apaga la ruleta ("La ruleta está en pausa").
  - `tiros_bienvenida` — tiros de regalo la primera vez, una vez por móvil (3).
  - `tiros_por_pedido` — tiros que suma cada ticket (3).
  - `dias_ticket` — antigüedad máxima del ticket que se acepta (7 días).
  - `bono_cada_5` — tiros de regalo en los tickets 5, 15, 25… (3).
  - `bono_cada_10` — tiros de regalo en los tickets 10, 20, 30… (6).
  - `max_pedidos_dia` — tickets que puede registrar un móvil por día (3). `0` = sin tope.
  - `max_jugadas_dia` — tope de tiros por móvil y por día (0 = sin tope; los tiros que sobran quedan para otro día).
  - `dias_entre_jugadas` — ya no se usa.
  - `dias_validez` — cuántos días dura un premio (30). Vale para los premios nuevos.
  - `max_premios_dia` — tope de premios por día (vacío = sin tope). Pasado el tope, todos pierden hasta el día siguiente.
- **Borrar a alguien** (si está mal cargado o lo pide, por RGPD): con la papelera en Caja → Jugadores, o en Table Editor → `premios_jugadores` → borrar su fila. Se borran solos sus pedidos y jugadas.
- **Regalarle tiros a alguien:** Table Editor → `premios_jugadores` → sumarle a su columna `tiros`. Los ve la próxima vez que abre la página.

## Límites a tener en cuenta

- Ni el móvil ni el número de pedido **se verifican** (no hay SMS ni conexión con Glovo): alguien podría inventar números de pedido. Por eso el tope de pedidos por móvil y por día, y en caja se ve el pedido de cada premio para compararlo con Glovo y se piden los últimos 3 números del móvil.
- La lista del local carga las últimas 3000 jugadas y hasta 10.000 jugadores; para más, exportar desde Supabase.
- El texto de privacidad es una base razonable, pero conviene que lo mire quien les lleve la parte legal.
