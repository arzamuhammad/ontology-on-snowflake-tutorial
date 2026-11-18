-- =====================================================================
-- 05_cortex_search.sql — Cortex Search services
--
--   PROCUREMENT_DOCS_SEARCH : unstructured policies / risk notes / contracts (both agents)
--   CONCEPT_SEARCH          : flattened GraphRAG index over ontology profiles (ontology agent only)
--                             -> resolves fuzzy wording / synonyms / Bahasa terms to a concept
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE ONTOLOGY_WH;
USE SCHEMA ONTOLOGY_DEMO.AGENTS;

ALTER TABLE ONTOLOGY_DEMO.RAW.PROCUREMENT_DOCS SET CHANGE_TRACKING = TRUE;

CREATE OR REPLACE CORTEX SEARCH SERVICE ONTOLOGY_DEMO.AGENTS.PROCUREMENT_DOCS_SEARCH
  ON CONTENT
  ATTRIBUTES DOC_TYPE
  WAREHOUSE = ONTOLOGY_WH
  TARGET_LAG = '1 day'
  AS SELECT DOC_ID, TITLE, DOC_TYPE, CONTENT FROM ONTOLOGY_DEMO.RAW.PROCUREMENT_DOCS;

CREATE OR REPLACE CORTEX SEARCH SERVICE ONTOLOGY_DEMO.AGENTS.CONCEPT_SEARCH
  ON PROFILE_TEXT
  ATTRIBUTES NODE_TYPE
  WAREHOUSE = ONTOLOGY_WH
  TARGET_LAG = '1 day'
  AS SELECT NODE_ID, NODE_TYPE, NAME, SQL_FILTER_HINT, PROFILE_TEXT
     FROM ONTOLOGY_DEMO.ONTOLOGY.CONCEPT_PROFILE;

-- Test the GraphRAG index: fuzzy / Bahasa wording -> concept
SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
  'ONTOLOGY_DEMO.AGENTS.CONCEPT_SEARCH',
  '{"query": "komponen pasif untuk PCB", "columns": ["NAME","NODE_TYPE","SQL_FILTER_HINT"], "limit": 3}'
)):results AS results;
