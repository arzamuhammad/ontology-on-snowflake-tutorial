-- =====================================================================
-- 99_cleanup.sql — remove everything created by this tutorial
-- =====================================================================
USE ROLE ACCOUNTADMIN;
DROP DATABASE IF EXISTS ONTOLOGY_DEMO;   -- tables, views, procedures, semantic views, search services, agents
DROP WAREHOUSE IF EXISTS ONTOLOGY_WH;
