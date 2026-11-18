-- =====================================================================
-- 04_semantic_views.sql — Layer 4: two semantic views on the SAME facts
--
--   PROCUREMENT_BASELINE_SV : what you get with "Cortex Analyst only" — flat ERP view
--   PROCUREMENT_ONTOLOGY_SV : same facts + ontology-derived dimensions
--                             (category hierarchy, ultimate parent, region)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE ONTOLOGY_WH;
USE SCHEMA ONTOLOGY_DEMO.AGENTS;

-- ---------------------------------------------------------------------
-- A. Baseline: flat ERP semantics
-- ---------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_SV
  TABLES (
    po AS ONTOLOGY_DEMO.RAW.PURCHASE_ORDERS PRIMARY KEY (PO_ID)
      COMMENT = 'Purchase order lines',
    items AS ONTOLOGY_DEMO.RAW.ITEMS PRIMARY KEY (ITEM_ID)
      COMMENT = 'Part master',
    cat AS ONTOLOGY_DEMO.RAW.ITEM_CATEGORY PRIMARY KEY (CATEGORY_CODE)
      COMMENT = 'ERP item category (flat list)',
    suppliers AS ONTOLOGY_DEMO.RAW.SUPPLIERS PRIMARY KEY (SUPPLIER_ID)
      COMMENT = 'Supplier master'
  )
  RELATIONSHIPS (
    po_item     AS po (ITEM_ID)      REFERENCES items,
    item_cat    AS items (CATEGORY_CODE) REFERENCES cat,
    po_supplier AS po (SUPPLIER_ID)  REFERENCES suppliers
  )
  FACTS (
    po.amount_usd AS AMOUNT_USD COMMENT = 'Line amount in USD',
    po.quantity   AS QUANTITY   COMMENT = 'Ordered quantity'
  )
  DIMENSIONS (
    po.po_id    AS PO_ID,
    po.po_date  AS PO_DATE WITH SYNONYMS = ('order date') COMMENT = 'Purchase order date',
    po.po_year  AS YEAR(PO_DATE) COMMENT = 'Year of the PO',
    po.po_month AS DATE_TRUNC('MONTH', PO_DATE) COMMENT = 'Month of the PO',
    po.plant    AS PLANT WITH SYNONYMS = ('factory', 'site') COMMENT = 'Receiving plant',
    items.item_name AS ITEM_NAME WITH SYNONYMS = ('part', 'material') COMMENT = 'Item / part name',
    cat.category_name AS CATEGORY_NAME WITH SYNONYMS = ('category') COMMENT = 'ERP item category',
    suppliers.supplier_name AS SUPPLIER_NAME WITH SYNONYMS = ('vendor') COMMENT = 'Supplier legal entity',
    suppliers.country_code  AS COUNTRY_CODE COMMENT = 'ISO country code of the supplier'
  )
  METRICS (
    po.total_spend    AS SUM(po.amount_usd) WITH SYNONYMS = ('spend', 'purchase value') COMMENT = 'Total spend in USD',
    po.po_line_count  AS COUNT(po.po_id) COMMENT = 'Number of PO lines',
    po.total_quantity AS SUM(po.quantity) COMMENT = 'Total quantity ordered'
  )
  COMMENT = 'Baseline procurement semantic view (flat ERP semantics, no ontology)';

-- ---------------------------------------------------------------------
-- B. Ontology-grounded: same facts, dimensions come from the ontology
-- ---------------------------------------------------------------------
CREATE OR REPLACE SEMANTIC VIEW ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_SV
  TABLES (
    po AS ONTOLOGY_DEMO.RAW.PURCHASE_ORDERS PRIMARY KEY (PO_ID)
      COMMENT = 'Purchase order lines',
    items AS ONTOLOGY_DEMO.RAW.ITEMS PRIMARY KEY (ITEM_ID)
      COMMENT = 'Part master',
    cat AS ONTOLOGY_DEMO.ONTOLOGY.VW_ONT_CATEGORY_PATH PRIMARY KEY (CATEGORY_CODE)
      COMMENT = 'Category taxonomy flattened from the ontology (one row per ERP leaf category)',
    suppliers AS ONTOLOGY_DEMO.ONTOLOGY.VW_ONT_SUPPLIER_HIERARCHY PRIMARY KEY (SUPPLIER_ID)
      COMMENT = 'Supplier with corporate ownership resolved from the knowledge graph'
  )
  RELATIONSHIPS (
    po_item     AS po (ITEM_ID)          REFERENCES items,
    item_cat    AS items (CATEGORY_CODE) REFERENCES cat,
    po_supplier AS po (SUPPLIER_ID)      REFERENCES suppliers
  )
  FACTS (
    po.amount_usd AS AMOUNT_USD COMMENT = 'Line amount in USD',
    po.quantity   AS QUANTITY   COMMENT = 'Ordered quantity'
  )
  DIMENSIONS (
    po.po_id    AS PO_ID,
    po.po_date  AS PO_DATE WITH SYNONYMS = ('order date') COMMENT = 'Purchase order date',
    po.po_year  AS YEAR(PO_DATE) COMMENT = 'Year of the PO',
    po.po_month AS DATE_TRUNC('MONTH', PO_DATE) COMMENT = 'Month of the PO',
    po.plant    AS PLANT WITH SYNONYMS = ('factory', 'site') COMMENT = 'Receiving plant',
    items.item_name AS ITEM_NAME WITH SYNONYMS = ('part', 'material') COMMENT = 'Item / part name',
    cat.leaf_category   AS LEAF_CATEGORY WITH SYNONYMS = ('category', 'ERP category')
      COMMENT = 'Most specific category (ERP leaf). Use IN-lists from the ontology tool for broader concepts.',
    cat.material_type   AS MATERIAL_TYPE COMMENT = 'Level 1: Direct Material or Indirect Material',
    cat.category_family AS CATEGORY_FAMILY
      COMMENT = 'Level 2: Electronic Component, Mechanical Component, Raw Material, Packaging Material, MRO Supply',
    cat.category_group  AS CATEGORY_GROUP
      COMMENT = 'Level 3: e.g. Passive Component, Semiconductor, Electromechanical Component, Fastener, Bearing, Metal, Polymer',
    cat.category_class  AS CATEGORY_CLASS
      COMMENT = 'Level 4: e.g. Capacitor, Resistor, Inductor, Integrated Circuit, Discrete Semiconductor',
    cat.category_path   AS CATEGORY_PATH COMMENT = 'Full taxonomy path, root to leaf',
    suppliers.supplier_name    AS SUPPLIER_NAME WITH SYNONYMS = ('vendor') COMMENT = 'Supplier legal entity',
    suppliers.immediate_parent AS IMMEDIATE_PARENT COMMENT = 'Direct owner of the supplier',
    suppliers.ultimate_parent  AS ULTIMATE_PARENT WITH SYNONYMS = ('supplier group', 'parent company', 'group')
      COMMENT = 'Ultimate parent company (resolved transitively). Use for concentration risk.',
    suppliers.ownership_status AS OWNERSHIP_STATUS COMMENT = 'Independent or Group member',
    suppliers.country          AS COUNTRY COMMENT = 'Supplier country',
    suppliers.sourcing_region  AS SOURCING_REGION WITH SYNONYMS = ('region') COMMENT = 'ASEAN or East Asia'
  )
  METRICS (
    po.total_spend    AS SUM(po.amount_usd) WITH SYNONYMS = ('spend', 'purchase value') COMMENT = 'Total spend in USD',
    po.po_line_count  AS COUNT(po.po_id) COMMENT = 'Number of PO lines',
    po.total_quantity AS SUM(po.quantity) COMMENT = 'Total quantity ordered'
  )
  COMMENT = 'Ontology-grounded procurement semantic view (taxonomy, ownership and geography from the knowledge graph)';

SHOW SEMANTIC VIEWS IN SCHEMA ONTOLOGY_DEMO.AGENTS;
