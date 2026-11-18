-- =====================================================================
-- 03_reasoning_layer.sql — Layer 3: reasoning generated from the graph
--
--   VW_ONT_CONCEPT_CLOSURE     recursive CTE: every (descendant, ancestor) pair (= subClassOf+)
--   VW_ONT_CONCEPT_EXPANSION   concept/composite  -> all ERP leaf categories it covers
--   VW_ONT_CATEGORY_PATH       one row per leaf: flattened hierarchy levels (no fan-out joins)
--   VW_ONT_SUPPLIER_HIERARCHY  supplier -> immediate parent -> ultimate parent, country, region
--   VW_ONT_ORG_MEMBERS         any organization/location -> all suppliers below it
--   CONCEPT_PROFILE            "flattened GraphRAG" document per node (indexed by Cortex Search)
--   ONTOLOGY_EXPAND(term)      deterministic tool: term/synonym -> concept + leaves + members + SQL hint
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE ONTOLOGY_WH;
USE SCHEMA ONTOLOGY_DEMO.ONTOLOGY;

-- ---------------------------------------------------------------------
-- 1. Transitive closure of SUBCLASS_OF (Recursive CTE ~ SPARQL rdfs:subClassOf*)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_ONT_CONCEPT_CLOSURE AS
WITH RECURSIVE up (DESCENDANT_ID, ANCESTOR_ID, DEPTH) AS (
  SELECT NODE_ID, NODE_ID, 0
  FROM KG_NODE WHERE NODE_TYPE = 'Concept'
  UNION ALL
  SELECT u.DESCENDANT_ID, e.DST_ID, u.DEPTH + 1
  FROM up u
  JOIN KG_EDGE e ON e.SRC_ID = u.ANCESTOR_ID AND e.EDGE_TYPE = 'SUBCLASS_OF'
  WHERE u.DEPTH < 15                       -- cycle / runaway guard
)
SELECT DESCENDANT_ID, ANCESTOR_ID, DEPTH FROM up;

-- ---------------------------------------------------------------------
-- 2. Concept -> ERP leaf categories (hierarchy + composite INCLUDES)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_ONT_CONCEPT_EXPANSION AS
WITH leaf AS (
  SELECT NODE_ID, NAME, PROPS:category_code::STRING AS CATEGORY_CODE
  FROM KG_NODE WHERE NODE_TYPE = 'Concept' AND PROPS:category_code::STRING IS NOT NULL
)
SELECT c.ANCESTOR_ID AS CONCEPT_ID, l.CATEGORY_CODE, l.NAME AS LEAF_CATEGORY
FROM VW_ONT_CONCEPT_CLOSURE c JOIN leaf l ON l.NODE_ID = c.DESCENDANT_ID
UNION
SELECT e.SRC_ID, l.CATEGORY_CODE, l.NAME
FROM KG_EDGE e
JOIN VW_ONT_CONCEPT_CLOSURE c ON c.ANCESTOR_ID = e.DST_ID
JOIN leaf l ON l.NODE_ID = c.DESCENDANT_ID
WHERE e.EDGE_TYPE = 'INCLUDES';

-- ---------------------------------------------------------------------
-- 3. Flattened category path per ERP leaf category (safe to join to facts: 1 row per code)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_ONT_CATEGORY_PATH AS
WITH anc AS (
  SELECT c.DESCENDANT_ID, n.NAME AS ANCESTOR_NAME, c.DEPTH,
         MAX(c.DEPTH) OVER (PARTITION BY c.DESCENDANT_ID) - c.DEPTH AS LEVEL_FROM_ROOT
  FROM VW_ONT_CONCEPT_CLOSURE c JOIN KG_NODE n ON n.NODE_ID = c.ANCESTOR_ID
)
SELECT
  l.PROPS:category_code::STRING                                         AS CATEGORY_CODE,
  l.NAME                                                                AS LEAF_CATEGORY,
  COALESCE(MAX(IFF(a.LEVEL_FROM_ROOT = 1, a.ANCESTOR_NAME, NULL)), l.NAME) AS MATERIAL_TYPE,
  COALESCE(MAX(IFF(a.LEVEL_FROM_ROOT = 2, a.ANCESTOR_NAME, NULL)), l.NAME) AS CATEGORY_FAMILY,
  COALESCE(MAX(IFF(a.LEVEL_FROM_ROOT = 3, a.ANCESTOR_NAME, NULL)), l.NAME) AS CATEGORY_GROUP,
  COALESCE(MAX(IFF(a.LEVEL_FROM_ROOT = 4, a.ANCESTOR_NAME, NULL)), l.NAME) AS CATEGORY_CLASS,
  LISTAGG(a.ANCESTOR_NAME, ' > ') WITHIN GROUP (ORDER BY a.DEPTH DESC)  AS CATEGORY_PATH
FROM KG_NODE l
JOIN anc a ON a.DESCENDANT_ID = l.NODE_ID
WHERE l.NODE_TYPE = 'Concept' AND l.PROPS:category_code::STRING IS NOT NULL
GROUP BY l.PROPS:category_code::STRING, l.NAME;

-- ---------------------------------------------------------------------
-- 4. Supplier ownership closure (SUBSIDIARY_OF is transitive)
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_ONT_SUPPLIER_HIERARCHY AS
WITH RECURSIVE own (SUPPLIER_NODE, ANCESTOR_ID, DEPTH) AS (
  SELECT NODE_ID, NODE_ID, 0 FROM KG_NODE WHERE NODE_TYPE = 'Supplier'
  UNION ALL
  SELECT o.SUPPLIER_NODE, e.DST_ID, o.DEPTH + 1
  FROM own o
  JOIN KG_EDGE e ON e.SRC_ID = o.ANCESTOR_ID AND e.EDGE_TYPE = 'SUBSIDIARY_OF'
  WHERE o.DEPTH < 10
),
top_parent AS (
  SELECT SUPPLIER_NODE, ANCESTOR_ID, DEPTH FROM own
  QUALIFY ROW_NUMBER() OVER (PARTITION BY SUPPLIER_NODE ORDER BY DEPTH DESC) = 1
)
SELECT
  s.PROPS:supplier_id::INT           AS SUPPLIER_ID,
  s.NAME                             AS SUPPLIER_NAME,
  COALESCE(p.NAME, s.NAME)           AS IMMEDIATE_PARENT,
  t.NAME                             AS ULTIMATE_PARENT,
  tp.DEPTH                           AS OWNERSHIP_LEVELS,
  IFF(tp.DEPTH = 0, 'Independent', 'Group member') AS OWNERSHIP_STATUS,
  cty.NAME                           AS COUNTRY,
  reg.NAME                           AS SOURCING_REGION
FROM KG_NODE s
JOIN top_parent tp ON tp.SUPPLIER_NODE = s.NODE_ID
JOIN KG_NODE t     ON t.NODE_ID = tp.ANCESTOR_ID
LEFT JOIN KG_EDGE pe ON pe.SRC_ID = s.NODE_ID AND pe.EDGE_TYPE = 'SUBSIDIARY_OF'
LEFT JOIN KG_NODE p  ON p.NODE_ID = pe.DST_ID
LEFT JOIN KG_EDGE le ON le.SRC_ID = s.NODE_ID AND le.EDGE_TYPE = 'LOCATED_IN'
LEFT JOIN KG_NODE cty ON cty.NODE_ID = le.DST_ID
LEFT JOIN KG_EDGE re ON re.SRC_ID = cty.NODE_ID AND re.EDGE_TYPE = 'PART_OF_REGION'
LEFT JOIN KG_NODE reg ON reg.NODE_ID = re.DST_ID
WHERE s.NODE_TYPE = 'Supplier';

-- ---------------------------------------------------------------------
-- 5. Organization / location -> all suppliers below it
-- ---------------------------------------------------------------------
CREATE OR REPLACE VIEW VW_ONT_ORG_MEMBERS AS
WITH RECURSIVE own (SUPPLIER_NODE, ANCESTOR_ID, DEPTH) AS (
  SELECT NODE_ID, NODE_ID, 0 FROM KG_NODE WHERE NODE_TYPE = 'Supplier'
  UNION ALL
  SELECT o.SUPPLIER_NODE, e.DST_ID, o.DEPTH + 1
  FROM own o
  JOIN KG_EDGE e ON e.SRC_ID = o.ANCESTOR_ID AND e.EDGE_TYPE IN ('SUBSIDIARY_OF')
  WHERE o.DEPTH < 10
)
SELECT o.ANCESTOR_ID AS ORG_ID, s.NAME AS SUPPLIER_NAME FROM own o JOIN KG_NODE s ON s.NODE_ID = o.SUPPLIER_NODE
UNION   -- country -> suppliers
SELECT le.DST_ID, s.NAME FROM KG_EDGE le JOIN KG_NODE s ON s.NODE_ID = le.SRC_ID WHERE le.EDGE_TYPE = 'LOCATED_IN'
UNION
SELECT re.DST_ID, s.NAME
FROM KG_EDGE le JOIN KG_EDGE re ON re.SRC_ID = le.DST_ID AND re.EDGE_TYPE = 'PART_OF_REGION'
JOIN KG_NODE s ON s.NODE_ID = le.SRC_ID
WHERE le.EDGE_TYPE = 'LOCATED_IN';   -- region -> suppliers

-- ---------------------------------------------------------------------
-- 6. Flattened GraphRAG profiles: one enriched document per ontology node
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE CONCEPT_PROFILE AS
WITH syn AS (
  SELECT NODE_ID, ARRAY_TO_STRING(PROPS:synonyms, ', ') AS SYNONYMS FROM KG_NODE
),
path AS (
  SELECT c.DESCENDANT_ID AS NODE_ID,
         LISTAGG(n.NAME, ' > ') WITHIN GROUP (ORDER BY c.DEPTH DESC) AS TAXONOMY_PATH
  FROM VW_ONT_CONCEPT_CLOSURE c JOIN KG_NODE n ON n.NODE_ID = c.ANCESTOR_ID
  GROUP BY 1
),
kids AS (
  SELECT e.DST_ID AS NODE_ID, LISTAGG(n.NAME, ', ') WITHIN GROUP (ORDER BY n.NAME) AS CHILDREN
  FROM KG_EDGE e JOIN KG_NODE n ON n.NODE_ID = e.SRC_ID
  WHERE e.EDGE_TYPE IN ('SUBCLASS_OF') GROUP BY 1
  UNION ALL
  SELECT e.SRC_ID, LISTAGG(n.NAME, ', ') WITHIN GROUP (ORDER BY n.NAME)
  FROM KG_EDGE e JOIN KG_NODE n ON n.NODE_ID = e.DST_ID
  WHERE e.EDGE_TYPE = 'INCLUDES' GROUP BY 1
),
leaves AS (
  SELECT CONCEPT_ID AS NODE_ID, ARRAY_AGG(DISTINCT LEAF_CATEGORY) WITHIN GROUP (ORDER BY LEAF_CATEGORY) AS LEAF_CATEGORIES
  FROM VW_ONT_CONCEPT_EXPANSION GROUP BY 1
),
members AS (
  SELECT ORG_ID AS NODE_ID, ARRAY_AGG(DISTINCT SUPPLIER_NAME) WITHIN GROUP (ORDER BY SUPPLIER_NAME) AS MEMBER_SUPPLIERS
  FROM VW_ONT_ORG_MEMBERS GROUP BY 1
)
SELECT
  n.NODE_ID,
  n.NODE_TYPE,
  n.NAME,
  s.SYNONYMS,
  n.PROPS:definition::STRING AS DEFINITION,
  p.TAXONOMY_PATH,
  k.CHILDREN,
  l.LEAF_CATEGORIES,
  m.MEMBER_SUPPLIERS,
  h.ULTIMATE_PARENT,
  CASE
    WHEN n.NODE_TYPE IN ('Concept','CompositeConcept') THEN
      'LEAF_CATEGORY IN (''' || ARRAY_TO_STRING(l.LEAF_CATEGORIES, ''',''') || ''')'
    WHEN n.NODE_TYPE = 'SupplierGroup' THEN 'ULTIMATE_PARENT = ''' || n.NAME || ''''
    WHEN n.NODE_TYPE = 'Supplier'      THEN 'SUPPLIER_NAME = ''' || n.NAME || ''''
    WHEN n.NODE_TYPE = 'Region'        THEN 'SOURCING_REGION = ''' || n.NAME || ''''
    WHEN n.NODE_TYPE = 'Country'       THEN 'COUNTRY = ''' || n.NAME || ''''
  END AS SQL_FILTER_HINT,
  -- the text that Cortex Search embeds + keyword-indexes
  n.NODE_TYPE || ': ' || n.NAME || '. '
  || IFF(s.SYNONYMS <> '', 'Also known as: ' || s.SYNONYMS || '. ', '')
  || COALESCE('Definition: ' || n.PROPS:definition::STRING || '. ', '')
  || COALESCE('Taxonomy path: ' || p.TAXONOMY_PATH || '. ', '')
  || COALESCE(IFF(n.NODE_TYPE = 'CompositeConcept', 'Includes: ', 'Sub-categories: ') || k.CHILDREN || '. ', '')
  || COALESCE('ERP leaf categories covered: ' || ARRAY_TO_STRING(l.LEAF_CATEGORIES, ', ') || '. ', '')
  || COALESCE('Member suppliers (all ownership levels): ' || ARRAY_TO_STRING(m.MEMBER_SUPPLIERS, ', ') || '. ', '')
  || COALESCE('Immediate parent: ' || NULLIF(h.IMMEDIATE_PARENT, h.SUPPLIER_NAME) || '. ', '')
  || COALESCE('Ultimate parent group: ' || NULLIF(h.ULTIMATE_PARENT, h.SUPPLIER_NAME) || '. ', '')
  || COALESCE('Country: ' || h.COUNTRY || ', region: ' || h.SOURCING_REGION || '.', '')
  AS PROFILE_TEXT
FROM KG_NODE n
LEFT JOIN syn s     ON s.NODE_ID = n.NODE_ID
LEFT JOIN path p    ON p.NODE_ID = n.NODE_ID
LEFT JOIN kids k    ON k.NODE_ID = n.NODE_ID
LEFT JOIN leaves l  ON l.NODE_ID = n.NODE_ID
LEFT JOIN members m ON m.NODE_ID = n.NODE_ID
LEFT JOIN VW_ONT_SUPPLIER_HIERARCHY h ON n.NODE_TYPE = 'Supplier' AND h.SUPPLIER_ID = n.PROPS:supplier_id::INT;

ALTER TABLE CONCEPT_PROFILE SET CHANGE_TRACKING = TRUE;

-- ---------------------------------------------------------------------
-- 7. Deterministic agent tool: resolve a business term through the ontology
-- ---------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE ONTOLOGY_EXPAND(TERM STRING)
RETURNS STRING
LANGUAGE SQL
COMMENT = 'Resolve a business term (name or synonym) to an ontology node and expand it to ERP leaf categories / member suppliers'
AS
$$
DECLARE
  node_id STRING;
  result  STRING;
BEGIN
  -- exact name > exact synonym > partial name > partial synonym
  node_id := (
    SELECT NODE_ID FROM (
      SELECT n.NODE_ID,
             MIN(CASE
                   WHEN LOWER(n.NAME) = LOWER(:TERM)                  THEN 1
                   WHEN LOWER(f.VALUE::STRING) = LOWER(:TERM)         THEN 2
                   WHEN n.NAME ILIKE '%' || :TERM || '%'              THEN 3
                   WHEN f.VALUE::STRING ILIKE '%' || :TERM || '%'     THEN 4
                 END) AS SCORE
      FROM ONTOLOGY_DEMO.ONTOLOGY.KG_NODE n,
           LATERAL FLATTEN(INPUT => n.PROPS:synonyms, OUTER => TRUE) f
      GROUP BY n.NODE_ID
      HAVING SCORE IS NOT NULL
      ORDER BY SCORE, LENGTH(n.NODE_ID)
      LIMIT 1));

  IF (node_id IS NULL) THEN
    RETURN TO_JSON(OBJECT_CONSTRUCT('matched', FALSE, 'term', :TERM,
           'hint', 'No ontology node matched. Call concept_search with the user wording to find the closest concept.'));
  END IF;

  result := (
    SELECT TO_JSON(OBJECT_CONSTRUCT(
             'matched', TRUE, 'term', :TERM, 'node_id', NODE_ID, 'node_type', NODE_TYPE,
             'name', NAME, 'synonyms', SYNONYMS, 'definition', DEFINITION,
             'taxonomy_path', TAXONOMY_PATH, 'children_or_includes', CHILDREN,
             'leaf_categories', LEAF_CATEGORIES, 'member_suppliers', MEMBER_SUPPLIERS,
             'ultimate_parent', ULTIMATE_PARENT, 'sql_filter_hint', SQL_FILTER_HINT))
    FROM ONTOLOGY_DEMO.ONTOLOGY.CONCEPT_PROFILE WHERE NODE_ID = :node_id);
  RETURN result;
END;
$$;

-- Quick tests
CALL ONTOLOGY_EXPAND('electronic component');
CALL ONTOLOGY_EXPAND('MLCC');
CALL ONTOLOGY_EXPAND('steel exposure');
CALL ONTOLOGY_EXPAND('Orion');
SELECT * FROM VW_ONT_CATEGORY_PATH ORDER BY CATEGORY_PATH;
SELECT * FROM VW_ONT_SUPPLIER_HIERARCHY ORDER BY ULTIMATE_PARENT, SUPPLIER_NAME;
