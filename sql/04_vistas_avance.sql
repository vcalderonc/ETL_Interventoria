-- ============================================================================
-- Vistas del TABLERO DE AVANCE (segmentación por proyecto, etapa, frente y
-- contratista). Son vistas NUEVAS: no modifican ninguna de 02_vistas.sql, así
-- que el Buscador y el Panel del director siguen funcionando igual.
--
-- Cómo se usa: ejecutar este archivo UNA vez en el SQL Editor de Neon con el
-- usuario administrador (neondb_owner). Es idempotente (CREATE OR REPLACE).
-- Para quitarlo todo:
--   DROP VIEW reporte.v_avance_cantidades, reporte.v_produccion_documental,
--             reporte.v_avance_documentos;
--
-- Cómo se obtiene el contratista: la ETL lo deduce de proyecto + etapa +
-- frente + fecha del documento, según la hoja FRENTES de la tabla maestra. No
-- depende de quién subió el archivo (en los datos actuales origen = PEI en
-- todos los documentos).
--
-- Sin contratista NO siempre es un error. Se rotula así:
--   Proyecto terminado (sin desglose)  proyecto TERMINADO: solo se clasifica
--                                      hasta proyecto (P003, P004).
--   Sin frente asignado                etapa o frente «ZZ» (general), o el
--                                      frente no tiene contratista en esa fecha.
--   Ejecuta PEI / sin contratista      el frente existe y su contratista está
--                                      vacío en la tabla maestra.
-- ============================================================================

-- 1. Un renglón por documento vigente, con nombres legibles y su contratista
CREATE OR REPLACE VIEW reporte.v_avance_documentos AS
SELECT
    d.nombre_base                                   AS documento,
    d.proyecto                                      AS cod_proyecto,
    p.nombre                                        AS proyecto,
    p.estado                                        AS estado_proyecto,
    d.etapa                                         AS cod_etapa,
    COALESCE(e.nombre, CASE WHEN d.etapa = 'ZZ' THEN 'General' ELSE d.etapa END)  AS etapa,
    d.frente                                        AS cod_frente,
    COALESCE(fa.nombre, CASE WHEN d.frente = 'ZZ' THEN 'General (sin frente)' ELSE d.frente END) AS frente,
    d.contratista                                   AS cod_contratista,
    COALESCE(
        c.nombre,
        CASE
            WHEN p.estado = 'TERMINADO'                THEN 'Proyecto terminado (sin desglose)'
            WHEN d.etapa = 'ZZ' OR d.frente = 'ZZ'     THEN 'Sin frente asignado'
            WHEN fa.contratista IS NULL AND fa.frente IS NOT NULL THEN 'Ejecuta PEI / sin contratista'
            ELSE 'Sin frente asignado'
        END
    )                                               AS contratista,
    d.tipo                                          AS cod_tipo,
    t.descripcion                                   AS tipo,
    d.fecha_documento,
    date_trunc('month', d.fecha_documento)::date    AS mes,
    a.version,
    a.enlace                                        AS abrir_en_drive
FROM ctrl.documento d
JOIN ctrl.archivo a        ON a.documento_id = d.id AND a.estado = 'VIGENTE'
LEFT JOIN ctrl.proyecto p  ON p.codigo = d.proyecto
LEFT JOIN ctrl.etapa e     ON e.proyecto = d.proyecto AND e.etapa = d.etapa
LEFT JOIN ctrl.tipo_documento t ON t.codigo = d.tipo
LEFT JOIN ctrl.contratista c    ON c.codigo = d.contratista
-- Fila de FRENTES que corresponde al documento: la vigente en su fecha; si la
-- fecha es anterior a todas, la primera (así el frente conserva su nombre).
LEFT JOIN LATERAL (
    SELECT f.frente, f.nombre, f.contratista
    FROM ctrl.frente_asignacion f
    WHERE f.proyecto = d.proyecto AND f.etapa = d.etapa AND f.frente = d.frente
    ORDER BY (f.fecha_inicio <= d.fecha_documento) DESC, f.fecha_inicio DESC
    LIMIT 1
) fa ON TRUE;

-- 2. Producción documental: cuántos documentos hay por proyecto, etapa,
--    frente, contratista y tipo. Mide ACTIVIDAD DOCUMENTAL, no avance físico.
CREATE OR REPLACE VIEW reporte.v_produccion_documental AS
SELECT cod_proyecto, proyecto, estado_proyecto, cod_etapa, etapa, cod_frente, frente,
       cod_contratista, contratista, cod_tipo, tipo, mes,
       COUNT(*)                AS documentos,
       MIN(fecha_documento)    AS primer_documento,
       MAX(fecha_documento)    AS ultimo_documento
FROM reporte.v_avance_documentos
GROUP BY cod_proyecto, proyecto, estado_proyecto, cod_etapa, etapa, cod_frente, frente,
         cod_contratista, contratista, cod_tipo, tipo, mes;

-- 3. Volúmenes por abscisa sumados por documento (corte, lleno, subbase).
--    Un renglón por documento: Looker los suma según el filtro.
--    CUIDADO: si cada documento es ACUMULADO (y no del período), sumar varios
--    documentos del mismo frente duplica el volumen. Confirmarlo con el
--    residente antes de mostrar totales al cliente.
CREATE OR REPLACE VIEW reporte.v_avance_cantidades AS
SELECT b.cod_proyecto, b.proyecto, b.cod_etapa, b.etapa, b.cod_frente, b.frente,
       b.cod_contratista, b.contratista, b.documento, b.fecha_documento, b.mes,
       COUNT(*)                    AS abscisas,
       SUM(q.volumen_corte)        AS volumen_corte,
       SUM(q.volumen_lleno)        AS volumen_lleno,
       SUM(q.volumen_lleno_sel)    AS volumen_lleno_sel,
       SUM(q.volumen_subbase)      AS volumen_subbase
FROM tecnico.cantidades_abscisa q
JOIN ctrl.archivo a   ON a.id = q.archivo_id AND a.estado = 'VIGENTE'
JOIN ctrl.documento d ON d.id = a.documento_id
JOIN reporte.v_avance_documentos b ON b.documento = d.nombre_base
GROUP BY b.cod_proyecto, b.proyecto, b.cod_etapa, b.etapa, b.cod_frente, b.frente,
         b.cod_contratista, b.contratista, b.documento, b.fecha_documento, b.mes;

-- Permiso de lectura para Looker (solo si el rol existe: en pruebas no existe)
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'lector_looker') THEN
        GRANT SELECT ON reporte.v_avance_documentos, reporte.v_produccion_documental,
                        reporte.v_avance_cantidades TO lector_looker;
    END IF;
END $$;
