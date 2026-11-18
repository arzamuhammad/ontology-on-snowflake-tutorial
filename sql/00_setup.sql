-- =====================================================================
-- 00_setup.sql — Environment for the Ontology-grounded Cortex Agent demo
-- Domain   : Procurement / supply chain (synthetic "PT Nusantara Manufaktur")
-- Creates  : warehouse, database, 3 schemas
-- Role     : ACCOUNTADMIN for simplicity (any role with CREATE DATABASE,
--            CREATE WAREHOUSE and SNOWFLAKE.CORTEX_USER also works)
-- =====================================================================
USE ROLE ACCOUNTADMIN;

CREATE WAREHOUSE IF NOT EXISTS ONTOLOGY_WH
  WAREHOUSE_SIZE = XSMALL
  AUTO_SUSPEND = 60
  AUTO_RESUME = TRUE
  INITIALLY_SUSPENDED = TRUE
  COMMENT = 'Ontology-grounded agent demo';

CREATE DATABASE IF NOT EXISTS ONTOLOGY_DEMO COMMENT = 'Ontology-grounded Cortex Agent demo';
CREATE SCHEMA IF NOT EXISTS ONTOLOGY_DEMO.RAW      COMMENT = 'Operational facts: POs, items, suppliers, documents';
CREATE SCHEMA IF NOT EXISTS ONTOLOGY_DEMO.ONTOLOGY COMMENT = 'Knowledge graph + ontology metadata + reasoning views';
CREATE SCHEMA IF NOT EXISTS ONTOLOGY_DEMO.AGENTS   COMMENT = 'Semantic views, Cortex Search services, Cortex Agents';

USE WAREHOUSE ONTOLOGY_WH;
USE DATABASE ONTOLOGY_DEMO;

-- If your region does not host the LLMs used by Cortex Agents, enable cross-region inference:
-- ALTER ACCOUNT SET CORTEX_ENABLED_CROSS_REGION = 'ANY_REGION';
