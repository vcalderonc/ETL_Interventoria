# Tablero de avance por proyecto, etapa, frente y contratista

Reporte **nuevo**, aparte del Buscador y del Panel del director (no se modifican). Responde la petición del cliente: ver de forma segmentada cuánto se ha hecho por proyecto, etapa, frente y contratista.

> Nota de nombre: Looker Studio ahora se llama **Data Studio**. Los documentos del proyecto y `docs/looker.md` todavía usan el nombre anterior.

## 1. Crear las vistas en la base (una sola vez)

1. En la consola de Neon, abre **SQL Editor** con el usuario administrador (`neondb_owner`).
2. Pega el contenido de `sql/04_vistas_avance.sql` y pulsa **Run**.
3. Comprueba con `SELECT * FROM reporte.v_produccion_documental LIMIT 20;`.

Solo se crean vistas nuevas: no se toca ninguna tabla ni vista existente. Para deshacerlo, ejecuta el `DROP VIEW` que está en el encabezado del archivo.

Las vistas se leen con el usuario `lector_looker`, igual que las demás (ver `docs/credenciales.md`).

## 2. Las tres vistas

| Vista | Qué contiene | Para qué sirve |
|---|---|---|
| `v_avance_documentos` | Un renglón por documento vigente, con proyecto, etapa, frente y contratista con nombre legible | Tabla de detalle y filtros |
| `v_produccion_documental` | Documentos por proyecto, etapa, frente, contratista, tipo y mes | Barras y tablas de actividad |
| `v_avance_cantidades` | Volúmenes de corte, lleno y subbase sumados por documento | Volúmenes por contratista y etapa |

**Qué mide cada una.** `v_produccion_documental` mide actividad documental (cuántos planos, carteras o contratos hay), no avance físico de obra. Rotúlalo así en el reporte. El avance físico solo puede salir de `v_avance_cantidades`, y hoy esos datos existen solo para algunos documentos de tipo CNT.

**Cómo se asigna el contratista.** Sale de la hoja FRENTES de la tabla maestra (proyecto + etapa + frente + fecha del documento). No depende de quién subió el archivo. Los rótulos sin contratista son:

- `Proyecto terminado (sin desglose)`: proyectos TERMINADOS, que solo se clasifican hasta proyecto.
- `Sin frente asignado`: etapa o frente «ZZ», o el frente no tiene contratista en esa fecha.
- `Ejecuta PEI / sin contratista`: el frente existe y su contratista está vacío.

## 3. Crear el reporte en Data Studio

1. Entra a Data Studio con la cuenta que creó los reportes actuales. Crea un **informe en blanco** nuevo y llámalo «Tablero de avance PEI».
2. **Agregar datos** → conector **PostgreSQL** → usa los mismos datos de conexión que el panel actual (`docs/looker.md`) y agrega las tres vistas como fuentes distintas.
3. Marca como **Dimensión** los campos de texto y fecha, y como **Métrica** `documentos`, `abscisas` y los `volumen_*`. Los volúmenes deben quedar con agregación **Suma**.

### Identidad visual

El logo está en `docs/assets/logo_pei.png`. En el reporte: **Insertar → Imagen** y súbelo en el encabezado.

Para los colores, en **Tema y diseño → Personalizar**:

| Uso | Color |
|---|---|
| Fondo de encabezado y texto | `#484848` |
| Color principal de gráficos | `#B82028` |
| Resalte | `#E81820` |

Son colores medidos sobre el membrete de la carta del beneficiario, no del manual de marca. Si el cliente tiene los códigos oficiales, úsalos.

### Páginas sugeridas

**Página 1: Producción por contratista y etapa** (fuente `v_produccion_documental`)
- Filtros arriba: `proyecto`, `etapa`, `frente`, `contratista`, `mes`.
- Barras: `documentos` por `contratista`, apiladas por `etapa`.
- Tabla: `proyecto`, `etapa`, `frente`, `contratista`, `tipo`, `documentos`, `ultimo_documento`.
- Tarjeta: total de documentos, y el porcentaje con contratista (campo calculado: `SUM(CASE WHEN cod_contratista IS NOT NULL THEN documentos ELSE 0 END) / SUM(documentos)`).

**Página 2: Volúmenes** (fuente `v_avance_cantidades`)
- Mismos filtros.
- Barras: `volumen_corte`, `volumen_lleno` y `volumen_subbase` por `contratista` y `etapa`.
- Texto fijo debajo: «Suma de los volúmenes por abscisa de los documentos de cantidades cargados. Puede duplicar volúmenes si los documentos son acumulados.»

**Página 3: Detalle** (fuente `v_avance_documentos`)
- Tabla con `documento`, `fecha_documento`, `tipo`, `contratista` y el enlace `abrir_en_drive`.

## 4. Antes de mostrar al cliente

- Confirmar con el residente si los documentos de cantidades son **acumulados o del período**.
- Los nombres de contratistas salen de la hoja CONTRATISTAS (EMS, WB, PCH, INYCEL, SOLUTEC, AE). Confirmar los nombres completos con el director.
- La asignación de frentes es de la prueba piloto y la debe confirmar el director.
- No existen aún archivos de presupuesto ni de cantidades ejecutadas por ítem (`presupuesto_cantidades` y `cantidades_ejecutadas` están vacías). Cuando existan, se agregará la vista de avance contra presupuesto.
