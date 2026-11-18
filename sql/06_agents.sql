-- =====================================================================
-- 06_agents.sql — Layer 5: two Cortex Agents for a side-by-side comparison
--
--   PROCUREMENT_BASELINE_AGENT : Cortex Analyst (flat SV) + Cortex Search (docs)
--   PROCUREMENT_ONTOLOGY_AGENT : Cortex Analyst (ontology SV) + Cortex Search (docs)
--                                + Cortex Search over concept profiles (GraphRAG)
--                                + ONTOLOGY_EXPAND stored procedure (deterministic graph lookup)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE ONTOLOGY_WH;
USE SCHEMA ONTOLOGY_DEMO.AGENTS;

-- ---------------------------------------------------------------------
-- A. Baseline agent
-- ---------------------------------------------------------------------
CREATE OR REPLACE AGENT ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_AGENT
  COMMENT = 'Baseline: Cortex Analyst + Cortex Search, no ontology'
  PROFILE = '{"display_name": "Procurement Agent (Baseline)", "color": "gray"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

orchestration:
  budget:
    seconds: 90
    tokens: 32000

instructions:
  response: |
    You are a procurement analyst assistant for PT Nusantara Manufaktur.
    Answer concisely, lead with the number, format USD values (e.g. $12.4M).
    State which categories or suppliers you included in the calculation.
  orchestration: |
    - Spend, quantity, supplier, category, plant or time questions: use procurement_analyst.
    - Policies, risk notes, contracts and strategies: use procurement_docs.
  sample_questions:
    - question: "What is our total spend on electronic components in 2026?"
    - question: "How much did we spend with the Orion group?"

tools:
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "procurement_analyst"
      description: "Structured procurement data: purchase order lines with spend, quantity, item, ERP category, supplier, country, plant and date."
  - tool_spec:
      type: "cortex_search"
      name: "procurement_docs"
      description: "Procurement policies, supplier risk notes, contract summaries and category strategies."
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generate charts from query results."

tool_resources:
  procurement_analyst:
    semantic_view: "ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_SV"
    execution_environment:
      type: warehouse
      warehouse: "ONTOLOGY_WH"
  procurement_docs:
    name: "ONTOLOGY_DEMO.AGENTS.PROCUREMENT_DOCS_SEARCH"
    max_results: "4"
    title_column: "TITLE"
    id_column: "DOC_ID"
$$;

-- ---------------------------------------------------------------------
-- B. Ontology-grounded agent
-- ---------------------------------------------------------------------
CREATE OR REPLACE AGENT ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_AGENT
  COMMENT = 'Ontology-grounded: Analyst on ontology SV + docs search + GraphRAG concept search + ontology expansion tool'
  PROFILE = '{"display_name": "Procurement Agent (Ontology)", "color": "blue"}'
  FROM SPECIFICATION
$$
models:
  orchestration: auto

orchestration:
  budget:
    seconds: 120
    tokens: 32000

instructions:
  response: |
    You are a procurement analyst assistant for PT Nusantara Manufaktur.
    Answer concisely, lead with the number, format USD values (e.g. $12.4M).
    Always explain HOW the business term was interpreted: name the ontology concept you resolved it to
    and list the leaf categories or member suppliers that were included (this is the audit trail).
    Answer in the language of the user (Bahasa Indonesia or English).
  orchestration: |
    GROUNDING FIRST. Business users use broad, informal or composite terms (e.g. "electronics",
    "passives", "chip", "MLCC", "APD", "baut", "steel exposure", "Orion group", "ASEAN suppliers").
    The ERP only stores leaf categories and legal entities, so NEVER guess with LIKE/ILIKE filters.

    Step 1 - Resolve every category, supplier-group or region term before querying:
      a. Call ontology_expand with the user's term (short noun phrase, e.g. "electronic component").
      b. If it returns matched=false, call concept_search with the user's wording, pick the best
         profile, then call ontology_expand again with that profile's NAME.
    Step 2 - Query procurement_analyst and pass the resolved scope EXPLICITLY in the question, using the
      sql_filter_hint, e.g. "total spend where LEAF_CATEGORY IN ('Ceramic Capacitor','Electrolytic Capacitor')"
      or "spend by supplier where ULTIMATE_PARENT = 'Orion Electronics Group'".
      For a whole hierarchy level you may also use MATERIAL_TYPE / CATEGORY_FAMILY / CATEGORY_GROUP /
      CATEGORY_CLASS columns.
    Step 3 - Use procurement_docs for policies, thresholds, risk notes and contracts. For policy-compliance
      questions (e.g. concentration limits), combine the policy threshold with the numbers.
    Supplier concentration is always measured at ULTIMATE_PARENT level.
  sample_questions:
    - question: "What is our total spend on electronic components in 2026?"
    - question: "How much did we spend with the Orion group, including all subsidiaries?"
    - question: "Berapa spend untuk material yang terekspos harga baja tahun 2026?"
    - question: "Does any supplier group breach our concentration policy?"

tools:
  - tool_spec:
      type: "generic"
      name: "ontology_expand"
      description: |
        Deterministic lookup in the procurement ontology (knowledge graph). Resolves a business term or synonym
        (category, composite concept, supplier, supplier group, country or region) to its ontology node and returns:
        taxonomy_path, children/includes, leaf_categories (ERP categories covered, incl. all descendants),
        member_suppliers (all ownership levels), ultimate_parent and a ready-to-use sql_filter_hint.
        When to use: BEFORE any spend query that mentions a category, group of suppliers or region.
        When NOT to use: pure date/plant questions, or policy text questions.
      input_schema:
        type: object
        properties:
          term:
            type: string
            description: "Short business term, e.g. 'electronic component', 'MLCC', 'steel exposure', 'Orion', 'ASEAN'"
        required: ["term"]
  - tool_spec:
      type: "cortex_search"
      name: "concept_search"
      description: |
        Semantic search over ontology concept profiles (name, synonyms in English and Bahasa, definition, taxonomy path,
        children, covered leaf categories, member suppliers). Use when ontology_expand finds no exact match or the
        user wording is vague / descriptive (e.g. "things we put on the PCB", "safety stuff for workers").
  - tool_spec:
      type: "cortex_analyst_text_to_sql"
      name: "procurement_analyst"
      description: |
        Structured procurement data enriched by the ontology: spend, quantity, PO lines by date, plant, item,
        LEAF_CATEGORY, MATERIAL_TYPE, CATEGORY_FAMILY, CATEGORY_GROUP, CATEGORY_CLASS, CATEGORY_PATH,
        supplier, IMMEDIATE_PARENT, ULTIMATE_PARENT, COUNTRY and SOURCING_REGION.
        Always include the resolved filter (from ontology_expand) in the question.
  - tool_spec:
      type: "cortex_search"
      name: "procurement_docs"
      description: "Procurement policies (thresholds, concentration limits), supplier risk notes, contract summaries and category strategies."
  - tool_spec:
      type: "data_to_chart"
      name: "data_to_chart"
      description: "Generate charts from query results."

tool_resources:
  ontology_expand:
    type: "procedure"
    identifier: "ONTOLOGY_DEMO.ONTOLOGY.ONTOLOGY_EXPAND"
    execution_environment:
      type: warehouse
      warehouse: "ONTOLOGY_WH"
      query_timeout: 60
  concept_search:
    name: "ONTOLOGY_DEMO.AGENTS.CONCEPT_SEARCH"
    max_results: "3"
    title_column: "NAME"
    id_column: "NODE_ID"
  procurement_analyst:
    semantic_view: "ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_SV"
    execution_environment:
      type: warehouse
      warehouse: "ONTOLOGY_WH"
  procurement_docs:
    name: "ONTOLOGY_DEMO.AGENTS.PROCUREMENT_DOCS_SEARCH"
    max_results: "4"
    title_column: "TITLE"
    id_column: "DOC_ID"
$$;

SHOW AGENTS IN SCHEMA ONTOLOGY_DEMO.AGENTS;

-- Make the agents visible in Snowflake Intelligence / CoWork (optional)
-- CREATE SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT;   -- once per account, if missing
-- ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_AGENT;
-- ALTER SNOWFLAKE INTELLIGENCE SNOWFLAKE_INTELLIGENCE_OBJECT_DEFAULT ADD AGENT ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_AGENT;
