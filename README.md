# Terry's Premios

La ruleta del QR del flyer. El cliente escanea, pone el **número de su pedido de Glovo**, nombre y móvil, gira una tragaperras de 3 rodillos con los personajes de Terry's y si salen **3 iguales** gana un premio con un código (`T-K7P3Q`) para canjear **en el local**. Cada jugada queda guardada en Supabase, así se va armando la base de clientes.

Publicada en GitHub Pages:

- Ruleta (a donde lleva el QR): https://jetraverso.github.io/terrys-premios/
- Caja: https://jetraverso.github.io/terrys-premios/local.html

Son dos páginas:

- **`index.html`** — la ruleta, a donde lleva el QR. Pensada para el móvil.
- **`local.html`** — para caja: canjear códigos, ver la base de jugadores (con CSV para Excel) y generar el QR del flyer. Pide email y contraseña.

La ruleta usa el estilo de Terry's: blanco y negro, con el logo y los personajes de los stickers. La página del local mantiene el diseño de Administración (modo noche).

## Cómo funciona

- **El resultado lo decide Supabase, no el navegador.** La página solo anima los rodillos hasta donde le dice el servidor, así nadie puede hacer trampa tocando el código de la página.
- **Una tirada por cada pedido de Glovo.** Para jugar hay que poner el número de pedido: en Glovo son **# y 3 números**. El `#` ya está puesto, así que el cliente solo escribe los 3 números. Como Glovo repite esos números, **cada número juega una vez por día** (a la hora de España): si la misma persona vuelve a pedir, vuelve a jugar. Si alguien pone un número que ya jugó ese día, le avisa (y si es el mismo cliente con un premio sin canjear, se lo vuelve a mostrar).
- **Freno a pedidos inventados:** como el número no se puede comprobar contra Glovo, un mismo móvil puede jugar como mucho **3 veces por día** (se cambia en `premios_config`). En caja se ve el número de pedido y el día de cada premio, así se puede comparar con los pedidos de Glovo de ese día antes de entregarlo.
- **El móvil** se guarda siempre igual (`600 11 12 22`, `+34600111222` y `0034600111222` son la misma persona) y en ese móvil la página recuerda los datos: la próxima vez solo hay que poner el pedido nuevo.
- **Premios y chances** (se cambian en Supabase, ver abajo):

  | 3 iguales | Imagen (`img/`) | Premio | Chance |
  |---|---|---|---|
  | Logo Terry's | `logo` | Menú Terry's gratis | 0,5 % |
  | Los Terry's (las dos burgers) | `burgers` | Burger Terry's gratis | 1 % |
  | Rumpi (perro) | `perro` | Burger Rumpi gratis | 1,5 % |
  | Buba (botella) | `botella` | Burger Buba gratis | 1,5 % |
  | Russel | `lata` | Burger Russel gratis | 1,5 % |
  | Torch | `bacon` | Burger Torch gratis | 1,5 % |
  | Zulma | `patatas` | Burger Zulma gratis | 1,5 % |
  | Copa Estrella | `cerveza` | Copa de cerveza gratis | 12 % |
  | — | | Sin premio | 79 % |

  O sea: de cada 100 jugadas salen más o menos 12 cañas, 8 burgers y medio menú. Las que no ganan muchas veces quedan "casi" (dos iguales), que es lo que hace que quieran volver a jugar.
- **El premio dura 30 días** y se canjea una sola vez.
- **El cliente se entera del canje:** el premio queda guardado en su móvil, y cada vez que abre la página (o vuelve a ella) le pregunta a la base cómo está. Si ya se canjeó, el aviso pasa a "✓ Premio canjeado" y la tarjeta muestra el código tachado con un sello de CANJEADO; si venció, desaparece. Con la tarjeta abierta se vuelve a mirar cada 15 segundos, así que si la está mostrando en caja cambia sola al rato. La base solo responde si coinciden el código y el móvil del ganador (`premios_estado`).
- **Base de datos:** número de pedido de cada jugada, nombre, móvil, email (opcional), si acepta promociones, cuántas veces jugó y ganó, de qué QR vino (`?o=flyer`), primera y última jugada.
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
- **Jugadores:** la base de clientes, con su **último pedido**, link a WhatsApp y CSV. Se puede buscar también por número de pedido.
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

En [`flyer/`](flyer/): **`terrys-flyer-A6.pdf`** para imprenta (A6, 10,5 × 14,8 cm, sin sangrado: los bordes son blancos) y **`terrys-flyer-A6.png`** (300 ppp) para mandar por WhatsApp o redes. El QR va a `…/terrys-premios/?o=flyer`, así en caja se ve quién vino por el flyer.

Para cambiarlo: se edita `flyer/flyer.html` (abriéndolo en el navegador se ve la hoja en grande) y se corre `flyer/exportar.sh`, que vuelve a generar el PDF y el PNG con Chrome. Antes de imprimir muchos, probá el QR impreso con un par de móviles.

## Cambiar cosas

Todo en Supabase → **Table Editor**:

- **`premios_catalogo`** — un renglón por personaje: `simbolo` (el nombre de su imagen en `img/`), `premio` y `probabilidad` (en %). Lo que falte para 100 es "sin premio". Con probabilidad 0 sigue saliendo en los rodillos pero nunca da premio. *Si cambiás un premio o agregás un personaje, cambialo también en la lista `PREMIOS` de `index.html` (es lo que muestra la página); un personaje nuevo necesita su imagen en `img/` (cuadrada, fondo transparente, `.webp`).*
- **`premios_config`**:
  - `activo` — `false` apaga la ruleta ("La ruleta está en pausa").
  - `max_jugadas_dia` — máximo de tiradas por móvil y por día (3). `0` = sin tope.
  - `dias_entre_jugadas` — días de espera entre tiradas de un mismo móvil, además del pedido (0 = ninguna: cada pedido juega).
  - `dias_validez` — cuántos días dura un premio (30). Vale para los premios nuevos.
  - `max_premios_dia` — tope de premios por día (vacío = sin tope). Pasado el tope, todos pierden hasta el día siguiente.
- **Borrar a alguien** (si lo pide, por RGPD): Table Editor → `premios_jugadores` → borrar su fila (se borran solas sus jugadas).

## Límites a tener en cuenta

- Ni el móvil ni el número de pedido **se verifican** (no hay SMS ni conexión con Glovo): alguien podría inventar números de pedido. Por eso el tope de tiradas por móvil y por día, y en caja se ve el pedido de cada premio para compararlo con Glovo y se piden los últimos 3 números del móvil.
- La lista del local carga las últimas 3000 jugadas y hasta 10.000 jugadores; para más, exportar desde Supabase.
- El texto de privacidad es una base razonable, pero conviene que lo mire quien les lleve la parte legal.
