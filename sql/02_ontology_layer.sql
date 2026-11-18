-- =====================================================================
-- 02_ontology_layer.sql — Knowledge graph + ontology metadata
--
--   Layer 1  KG_NODE / KG_EDGE      : universal object–relationship storage
--   Layer 2  ONT_CLASS / ONT_RELATION_DEF : meaning declared as metadata
--
-- What the ontology knows that the ERP does not:
--   * the category TAXONOMY   (Ceramic Capacitor → Capacitor → Passive → Electronic → Direct)
--   * SYNONYMS                (MLCC, elko, MCU, APD, baut, chip, semikonduktor ...)
--   * COMPOSITE concepts      ("Steel-Price-Exposed Material" = Steel Coil + Fasteners + Bearings)
--   * CORPORATE OWNERSHIP     (Kirana Passive Tech → Orion Components Indonesia → Orion Group)
--   * GEOGRAPHY               (country → region)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE ONTOLOGY_WH;
USE SCHEMA ONTOLOGY_DEMO.ONTOLOGY;

-- ---------------------------------------------------------------------
-- Layer 1 — physical graph storage
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE KG_NODE (
  NODE_ID     STRING PRIMARY KEY,
  NODE_TYPE   STRING NOT NULL,   -- Concept | CompositeConcept | Supplier | SupplierGroup | Country | Region
  NAME        STRING,
  PROPS       VARIANT,           -- definition, synonyms[], category_code, erp ids ...
  TS_INGESTED TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) CLUSTER BY (NODE_TYPE);

CREATE OR REPLACE TABLE KG_EDGE (
  EDGE_ID         STRING PRIMARY KEY,
  SRC_ID          STRING NOT NULL,
  DST_ID          STRING NOT NULL,
  EDGE_TYPE       STRING NOT NULL, -- SUBCLASS_OF | INCLUDES | SUBSIDIARY_OF | LOCATED_IN | PART_OF_REGION
  WEIGHT          FLOAT DEFAULT 1.0,
  PROPS           VARIANT,
  EFFECTIVE_START DATE,
  EFFECTIVE_END   DATE,
  TS_INGESTED     TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
) CLUSTER BY (EDGE_TYPE, SRC_ID, DST_ID);

-- ---------------------------------------------------------------------
-- Layer 2 — ontology metadata (the "schema of meaning")
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ONT_CLASS (
  CLASS_NAME   STRING PRIMARY KEY,
  PARENT_CLASS STRING,
  IS_ABSTRACT  BOOLEAN,
  DESCRIPTION  STRING
);
INSERT INTO ONT_CLASS VALUES
  ('Thing',            NULL,      TRUE,  'Root of everything in the ontology'),
  ('Concept',          'Thing',   FALSE, 'A material category in the procurement taxonomy'),
  ('CompositeConcept', 'Concept', FALSE, 'A business concept defined as a union of other concepts across branches'),
  ('Organization',     'Thing',   TRUE,  'Any legal or corporate entity'),
  ('Supplier',         'Organization', FALSE, 'A legal entity that receives purchase orders'),
  ('SupplierGroup',    'Organization', FALSE, 'Ultimate parent company of one or more suppliers'),
  ('Location',         'Thing',   TRUE,  'Geographic entity'),
  ('Country',          'Location', FALSE, 'Country of a supplier legal entity'),
  ('Region',           'Location', FALSE, 'Sourcing region grouping countries');

CREATE OR REPLACE TABLE ONT_RELATION_DEF (
  REL_NAME      STRING PRIMARY KEY,
  DOMAIN_CLASS  STRING,
  RANGE_CLASS   STRING,
  CARDINALITY   STRING,
  IS_TRANSITIVE BOOLEAN,
  INVERSE_NAME  STRING,
  DESCRIPTION   STRING
);
INSERT INTO ONT_RELATION_DEF VALUES
  ('SUBCLASS_OF',    'Concept',          'Concept',      'N:1', TRUE,  'HAS_SUBCLASS',   'Taxonomy: child category is a kind of parent category'),
  ('INCLUDES',       'CompositeConcept', 'Concept',      'N:M', FALSE, 'INCLUDED_IN',    'Composite business concept includes these concepts (and all their descendants)'),
  ('SUBSIDIARY_OF',  'Organization',     'Organization', 'N:1', TRUE,  'PARENT_OF',      'Corporate ownership; transitive up to the ultimate parent'),
  ('LOCATED_IN',     'Supplier',         'Country',      'N:1', FALSE, 'HOSTS',          'Country of the supplier legal entity'),
  ('PART_OF_REGION', 'Country',          'Region',       'N:1', FALSE, 'CONTAINS',       'Country belongs to a sourcing region');

-- ---------------------------------------------------------------------
-- Concept taxonomy (could equally be loaded from OWL/SKOS/RDF, e.g. UNSPSC, eCl@ss, GS1)
-- columns: id, name, parent, erp category_code, definition, synonyms (pipe separated)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TEMPORARY TABLE _CONCEPTS (ID STRING, NAME STRING, PARENT STRING, CODE STRING, DEF STRING, SYN STRING);
INSERT INTO _CONCEPTS VALUES
 ('C:ROOT','Purchased Material',NULL,NULL,'Anything the company buys','all spend|total spend|semua pembelian'),
 ('C:DIRECT','Direct Material','C:ROOT',NULL,'Material that goes into the finished product (bill of materials)','direct spend|BOM material|bahan langsung'),
 ('C:INDIRECT','Indirect Material','C:ROOT',NULL,'Material that supports operations but is not part of the product','indirect spend|non-production|bahan tidak langsung'),
 ('C:ELEC','Electronic Component','C:DIRECT',NULL,'Components assembled on printed circuit boards','electronics|e-components|komponen elektronik|electronic parts'),
 ('C:PASSIVE','Passive Component','C:ELEC',NULL,'Electronic components that do not amplify signals','passives|komponen pasif'),
 ('C:CAP','Capacitor','C:PASSIVE',NULL,'Stores electrical charge','kapasitor|kondensator|caps'),
 ('C:CER_CAP','Ceramic Capacitor','C:CAP','CER_CAP','Multilayer ceramic chip capacitor','MLCC|multilayer ceramic capacitor|kapasitor keramik'),
 ('C:ELE_CAP','Electrolytic Capacitor','C:CAP','ELE_CAP','Aluminium electrolytic capacitor','elko|e-cap|aluminium electrolytic'),
 ('C:RES','Resistor','C:PASSIVE',NULL,'Limits electrical current','resistor|hambatan'),
 ('C:TF_RES','Thick Film Resistor','C:RES','TF_RES','SMD thick film chip resistor','chip resistor|SMD resistor'),
 ('C:IND','Inductor','C:PASSIVE',NULL,'Stores energy in a magnetic field','coil|choke|induktor'),
 ('C:PWR_IND','Power Inductor','C:IND','PWR_IND','SMD power inductor for DC-DC conversion','power coil|power choke'),
 ('C:SEMI','Semiconductor','C:ELEC',NULL,'Active electronic components made from semiconductor material','semis|semikonduktor|active component|komponen aktif'),
 ('C:IC','Integrated Circuit','C:SEMI',NULL,'Packaged integrated circuit','IC|chip|chips|cip'),
 ('C:MCU','Microcontroller','C:IC','MCU','Single-chip computer with CPU, memory and IO','MCU|mikrokontroler|micro|microcontroller unit'),
 ('C:MEM_IC','Memory IC','C:IC','MEM_IC','DRAM and flash memory devices','memory|DRAM|flash|memori'),
 ('C:PMIC','Power Management IC','C:IC','PMIC','Voltage regulators and DC-DC converters','PMIC|regulator|power IC|voltage regulator|LDO|buck converter'),
 ('C:DISCRETE','Discrete Semiconductor','C:SEMI',NULL,'Single-function semiconductor devices','discretes|diskrit'),
 ('C:MOSFET','Power MOSFET','C:DISCRETE','MOSFET','Power switching transistor','MOSFET|transistor|power transistor'),
 ('C:DIODE','Schottky Diode','C:DISCRETE','DIODE','Rectifier diode','diode|dioda|rectifier'),
 ('C:EMECH','Electromechanical Component','C:ELEC',NULL,'Components with moving or mating parts','electromechanical|interconnect|elektromekanik'),
 ('C:CONN','Connector','C:EMECH','CONN','Board and cable connectors','konektor|header|receptacle|USB-C'),
 ('C:RELAY','Relay','C:EMECH','RELAY','Electrically operated switch','relai|automotive relay'),
 ('C:MECH','Mechanical Component','C:DIRECT',NULL,'Machined or formed mechanical parts','mechanical parts|komponen mekanik'),
 ('C:FASTENER','Fastener','C:MECH',NULL,'Bolts, screws and nuts','fasteners|hardware|baut dan mur'),
 ('C:HEX_BOLT','Hex Bolt','C:FASTENER','HEX_BOLT','Hexagon head bolt','bolt|baut'),
 ('C:MACH_SCREW','Machine Screw','C:FASTENER','MACH_SCREW','Machine screw','screw|sekrup'),
 ('C:HEX_NUT','Hex Nut','C:FASTENER','HEX_NUT','Hexagon nut','nut|mur'),
 ('C:BEARING','Bearing','C:MECH',NULL,'Rolling element bearings','bantalan|laher|bearings'),
 ('C:BALL_BRG','Ball Bearing','C:BEARING','BALL_BRG','Deep groove ball bearing','ball bearing|deep groove bearing'),
 ('C:RAWMAT','Raw Material','C:DIRECT',NULL,'Unprocessed or semi-processed material','raw materials|bahan baku'),
 ('C:METAL','Metal','C:RAWMAT',NULL,'Ferrous and non-ferrous metals','metals|logam'),
 ('C:STEEL_COIL','Steel Coil','C:METAL','STEEL_COIL','Cold rolled steel coil','steel|baja|CRC|cold rolled coil|SPCC'),
 ('C:ALU_INGOT','Aluminium Ingot','C:METAL','ALU_INGOT','Aluminium casting alloy ingot','aluminum|aluminium|alu|A356'),
 ('C:POLYMER','Polymer','C:RAWMAT',NULL,'Plastics and polymers','plastics|plastik'),
 ('C:PLASTIC_RESIN','Plastic Resin','C:POLYMER','PLASTIC_RESIN','Thermoplastic pellets','resin|ABS|polycarbonate|biji plastik'),
 ('C:PACK','Packaging Material','C:INDIRECT',NULL,'Outbound packaging','packaging|kemasan'),
 ('C:CARTON','Corrugated Carton','C:PACK','CARTON','Corrugated shipping box','carton|box|kardus'),
 ('C:PALLET','Wooden Pallet','C:PACK','PALLET','Heat-treated wooden pallet','pallet|palet'),
 ('C:MRO','MRO Supply','C:INDIRECT',NULL,'Maintenance, repair and operations supplies','MRO|maintenance repair and operations|consumables'),
 ('C:LUBRICANT','Industrial Lubricant','C:MRO','LUBRICANT','Hydraulic oils and greases','oil|oli|grease|pelumas'),
 ('C:PPE','Personal Protective Equipment','C:MRO','PPE','Helmets, gloves and other safety gear','PPE|APD|alat pelindung diri|safety gear'),
 -- composite business concepts (cut across branches — cannot be expressed as a single tree node)
 ('C:STEEL_EXPOSED','Steel-Price-Exposed Material',NULL,NULL,'All material whose cost follows the steel price index: steel coil, fasteners and bearings','steel exposure|steel-based material|exposed to steel price|material berbasis baja'),
 ('C:ALLOC_CHIPS','Allocation-Constrained Chips',NULL,NULL,'Chips currently on foundry allocation with long lead times: microcontrollers and memory','chip shortage|long lead-time chips|chip langka|allocation chips');

INSERT INTO KG_NODE (NODE_ID, NODE_TYPE, NAME, PROPS)
SELECT ID,
       IFF(ID IN ('C:STEEL_EXPOSED','C:ALLOC_CHIPS'), 'CompositeConcept', 'Concept'),
       NAME,
       OBJECT_CONSTRUCT_KEEP_NULL('definition', DEF,
                                  'category_code', CODE,
                                  'synonyms', SPLIT(SYN, '|'))
FROM _CONCEPTS;

INSERT INTO KG_EDGE (EDGE_ID, SRC_ID, DST_ID, EDGE_TYPE)
SELECT 'E:SUB:' || ID, ID, PARENT, 'SUBCLASS_OF' FROM _CONCEPTS WHERE PARENT IS NOT NULL;

INSERT INTO KG_EDGE (EDGE_ID, SRC_ID, DST_ID, EDGE_TYPE) VALUES
  ('E:INC:1','C:STEEL_EXPOSED','C:STEEL_COIL','INCLUDES'),
  ('E:INC:2','C:STEEL_EXPOSED','C:FASTENER','INCLUDES'),
  ('E:INC:3','C:STEEL_EXPOSED','C:BEARING','INCLUDES'),
  ('E:INC:4','C:ALLOC_CHIPS','C:MCU','INCLUDES'),
  ('E:INC:5','C:ALLOC_CHIPS','C:MEM_IC','INCLUDES');

-- ---------------------------------------------------------------------
-- Organizations: suppliers (from ERP) + supplier groups (from e.g. D&B / legal entity data)
-- ---------------------------------------------------------------------
INSERT INTO KG_NODE (NODE_ID, NODE_TYPE, NAME, PROPS)
SELECT 'S:' || SUPPLIER_ID, 'Supplier', SUPPLIER_NAME,
       OBJECT_CONSTRUCT('supplier_id', SUPPLIER_ID, 'country_code', COUNTRY_CODE,
                        'synonyms', ARRAY_CONSTRUCT())
FROM ONTOLOGY_DEMO.RAW.SUPPLIERS;

INSERT INTO KG_NODE (NODE_ID, NODE_TYPE, NAME, PROPS)
SELECT column1, 'SupplierGroup', column2,
       OBJECT_CONSTRUCT('hq_country', column3, 'synonyms', SPLIT(column4, '|'))
FROM VALUES
  ('G:ORION',  'Orion Electronics Group',      'JP', 'Orion|Orion group'),
  ('G:HELIX',  'Helix Semiconductor Holdings', 'TW', 'Helix|Helix group'),
  ('G:BAJA',   'Baja Nusantara Group',         'ID', 'Baja Nusantara|BNG'),
  ('G:PACIFIC','Pacific Polymer Corp',         'TH', 'Pacific Polymer');

INSERT INTO KG_EDGE (EDGE_ID, SRC_ID, DST_ID, EDGE_TYPE, PROPS, EFFECTIVE_START)
SELECT 'E:OWN:' || column1, column1, column2, 'SUBSIDIARY_OF',
       OBJECT_CONSTRUCT('ownership_pct', column3), column4::DATE
FROM VALUES
  ('S:101','G:ORION',  100, '2010-01-01'),
  ('S:102','S:101',     80, '2019-06-01'),   -- 2 levels deep: Kirana -> Orion Indonesia -> Orion Group
  ('S:103','G:ORION',  100, '2012-01-01'),
  ('S:104','G:HELIX',  100, '2008-01-01'),
  ('S:105','G:HELIX',   65, '2025-03-01'),   -- acquisition: name gives no hint
  ('S:106','G:BAJA',   100, '2005-01-01'),
  ('S:107','G:BAJA',    70, '2016-01-01'),
  ('S:108','G:PACIFIC',100, '2011-01-01');

-- Geography
INSERT INTO KG_NODE (NODE_ID, NODE_TYPE, NAME, PROPS)
SELECT column1, column2, column3, OBJECT_CONSTRUCT('synonyms', SPLIT(column4, '|'))
FROM VALUES
  ('R:ASEAN','Region','ASEAN','Southeast Asia|Asia Tenggara|SEA'),
  ('R:EASIA','Region','East Asia','Asia Timur|North Asia'),
  ('CTY:ID','Country','Indonesia','ID|RI'),
  ('CTY:MY','Country','Malaysia','MY'),
  ('CTY:SG','Country','Singapore','SG'),
  ('CTY:TH','Country','Thailand','TH'),
  ('CTY:TW','Country','Taiwan','TW'),
  ('CTY:CN','Country','China','CN|Tiongkok'),
  ('CTY:JP','Country','Japan','JP|Jepang');

INSERT INTO KG_EDGE (EDGE_ID, SRC_ID, DST_ID, EDGE_TYPE)
SELECT 'E:REG:' || column1, column1, column2, 'PART_OF_REGION'
FROM VALUES ('CTY:ID','R:ASEAN'),('CTY:MY','R:ASEAN'),('CTY:SG','R:ASEAN'),('CTY:TH','R:ASEAN'),
            ('CTY:TW','R:EASIA'),('CTY:CN','R:EASIA'),('CTY:JP','R:EASIA');

INSERT INTO KG_EDGE (EDGE_ID, SRC_ID, DST_ID, EDGE_TYPE)
SELECT 'E:LOC:' || SUPPLIER_ID, 'S:' || SUPPLIER_ID, 'CTY:' || COUNTRY_CODE, 'LOCATED_IN'
FROM ONTOLOGY_DEMO.RAW.SUPPLIERS;

-- Sanity check
SELECT NODE_TYPE, COUNT(*) AS n FROM KG_NODE GROUP BY 1
UNION ALL
SELECT 'edge:' || EDGE_TYPE, COUNT(*) FROM KG_EDGE GROUP BY 1
ORDER BY 1;
