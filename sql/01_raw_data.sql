-- =====================================================================
-- 01_raw_data.sql — Synthetic operational data (what a typical ERP holds)
--
-- IMPORTANT DESIGN POINT FOR THE DEMO:
--   The ERP only knows the *leaf* category of an item (e.g. "Ceramic Capacitor").
--   It has NO idea that a Ceramic Capacitor is a Capacitor, a Passive Component,
--   an Electronic Component and a Direct Material. It also does not know that
--   "Kirana Passive Tech" is owned by "Orion Electronics Group".
--   That missing knowledge is exactly what the ontology adds in 02_*.sql.
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE ONTOLOGY_WH;
USE SCHEMA ONTOLOGY_DEMO.RAW;

-- ---------------------------------------------------------------------
-- 1. Flat leaf-category list (as configured in the ERP)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ITEM_CATEGORY (
  CATEGORY_CODE STRING PRIMARY KEY,
  CATEGORY_NAME STRING
) COMMENT = 'Flat ERP category list (leaf level only, no hierarchy)';

INSERT INTO ITEM_CATEGORY VALUES
  ('CER_CAP','Ceramic Capacitor'), ('ELE_CAP','Electrolytic Capacitor'),
  ('TF_RES','Thick Film Resistor'), ('PWR_IND','Power Inductor'),
  ('MCU','Microcontroller'), ('MEM_IC','Memory IC'), ('PMIC','Power Management IC'),
  ('MOSFET','Power MOSFET'), ('DIODE','Schottky Diode'),
  ('CONN','Connector'), ('RELAY','Relay'),
  ('HEX_BOLT','Hex Bolt'), ('MACH_SCREW','Machine Screw'), ('HEX_NUT','Hex Nut'),
  ('BALL_BRG','Ball Bearing'),
  ('STEEL_COIL','Steel Coil'), ('ALU_INGOT','Aluminium Ingot'), ('PLASTIC_RESIN','Plastic Resin'),
  ('CARTON','Corrugated Carton'), ('PALLET','Wooden Pallet'),
  ('LUBRICANT','Industrial Lubricant'), ('PPE','Personal Protective Equipment');

-- ---------------------------------------------------------------------
-- 2. Items (part master) — names deliberately do NOT reveal the hierarchy
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE ITEMS (
  ITEM_ID INT PRIMARY KEY,
  ITEM_NAME STRING,
  CATEGORY_CODE STRING,
  UOM STRING,
  BASE_PRICE_USD NUMBER(12,4),
  MAX_QTY INT
) COMMENT = 'Part master';

INSERT INTO ITEMS VALUES
  ( 1,'MLCC 100nF 0603 X7R','CER_CAP','PCS',0.0080,200000),
  ( 2,'MLCC 10uF 0805 X5R','CER_CAP','PCS',0.0300,100000),
  ( 3,'Alu Elko 470uF 35V','ELE_CAP','PCS',0.1200,40000),
  ( 4,'Alu Elko 1000uF 16V','ELE_CAP','PCS',0.1500,40000),
  ( 5,'Chip Res 10k 0603 1%','TF_RES','PCS',0.0020,300000),
  ( 6,'Chip Res 4.7k 0402 1%','TF_RES','PCS',0.0015,300000),
  ( 7,'SMD Inductor 4.7uH 3A','PWR_IND','PCS',0.2500,30000),
  ( 8,'ARM Cortex-M4 MCU 512KB','MCU','PCS',3.8000,20000),
  ( 9,'8-bit MCU 32KB','MCU','PCS',0.9000,30000),
  (10,'DDR4 8Gb DRAM','MEM_IC','PCS',2.6000,20000),
  (11,'SPI NOR Flash 128Mb','MEM_IC','PCS',0.8500,30000),
  (12,'Buck Converter 3A 18V','PMIC','PCS',0.7000,30000),
  (13,'LDO 500mA 3.3V','PMIC','PCS',0.1800,50000),
  (14,'N-Ch MOSFET 60V 30A','MOSFET','PCS',0.4500,40000),
  (15,'Schottky 40V 3A SMA','DIODE','PCS',0.0600,80000),
  (16,'Board-to-Board Conn 40P','CONN','PCS',0.5500,30000),
  (17,'USB-C Receptacle 16P','CONN','PCS',0.3500,30000),
  (18,'Automotive Relay 12V 40A','RELAY','PCS',1.2000,10000),
  (19,'Hex Bolt M8x30 Gr 8.8','HEX_BOLT','PCS',0.0900,100000),
  (20,'Pan Head Screw M3x8','MACH_SCREW','PCS',0.0200,200000),
  (21,'Hex Nut M8 Zinc','HEX_NUT','PCS',0.0300,150000),
  (22,'Deep Groove 6204-2RS','BALL_BRG','PCS',1.8000,8000),
  (23,'CR Coil 1.2mm SPCC','STEEL_COIL','TON',780.0000,60),
  (24,'Ingot A356','ALU_INGOT','TON',2450.0000,25),
  (25,'ABS Pellet Natural','PLASTIC_RESIN','KG',1.7000,20000),
  (26,'PC Pellet Clear','PLASTIC_RESIN','KG',2.9000,10000),
  (27,'Double Wall Box 60x40','CARTON','PCS',0.9000,20000),
  (28,'HT Pallet 1200x1000','PALLET','PCS',9.5000,2000),
  (29,'Hydraulic Oil ISO VG46','LUBRICANT','LTR',2.4000,3000),
  (30,'Safety Helmet Type II','PPE','PCS',6.5000,1000),
  (31,'Cut-Resistant Gloves L5','PPE','PAIR',3.2000,3000);

-- ---------------------------------------------------------------------
-- 3. Suppliers — the ERP holds a flat list; ownership lives elsewhere
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE SUPPLIERS (
  SUPPLIER_ID INT PRIMARY KEY,
  SUPPLIER_NAME STRING,
  COUNTRY_CODE STRING
) COMMENT = 'Supplier master (flat, no corporate hierarchy)';

INSERT INTO SUPPLIERS VALUES
  (101,'Orion Components Indonesia','ID'),
  (102,'Kirana Passive Tech','ID'),
  (103,'Orion Semicon Malaysia','MY'),
  (104,'Helix Semiconductor Taiwan','TW'),
  (105,'Nova Chip Solutions','SG'),
  (106,'Baja Nusantara Steel','ID'),
  (107,'Mitra Fastener Abadi','ID'),
  (108,'Pacific Polymer Thailand','TH'),
  (109,'Sinar Kemas Packaging','ID'),
  (110,'Prima Safety Indonesia','ID'),
  (111,'Lubritech Asia','SG'),
  (112,'Volta Connect','CN'),
  (113,'Delta Relay Works','CN'),
  (114,'Sakura Bearing','JP');

-- Approved vendor list: which suppliers may deliver which category
CREATE OR REPLACE TABLE APPROVED_VENDOR_LIST (
  CATEGORY_CODE STRING, SUPPLIER_ID INT, SEQ INT
);
INSERT INTO APPROVED_VENDOR_LIST VALUES
  ('CER_CAP',101,1),('CER_CAP',102,2),('CER_CAP',103,3),
  ('ELE_CAP',101,1),('ELE_CAP',102,2),
  ('TF_RES',102,1),('TF_RES',101,2),
  ('PWR_IND',101,1),('PWR_IND',103,2),
  ('MCU',104,1),('MCU',105,2),('MCU',103,3),
  ('MEM_IC',104,1),('MEM_IC',105,2),
  ('PMIC',105,1),('PMIC',103,2),
  ('MOSFET',104,1),('MOSFET',103,2),
  ('DIODE',103,1),('DIODE',104,2),
  ('CONN',112,1),('RELAY',113,1),
  ('HEX_BOLT',107,1),('MACH_SCREW',107,1),('HEX_NUT',107,1),
  ('BALL_BRG',114,1),
  ('STEEL_COIL',106,1),('ALU_INGOT',106,1),
  ('PLASTIC_RESIN',108,1),
  ('CARTON',109,1),('PALLET',109,1),
  ('LUBRICANT',111,1),('PPE',110,1);

-- ---------------------------------------------------------------------
-- 4. Purchase orders — 20,000 synthetic lines, Jan-2025 .. Oct-2026
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE PURCHASE_ORDERS AS
WITH gen AS (
  SELECT
    SEQ4() + 1                                         AS rn,
    UNIFORM(1, 31, RANDOM(11))                         AS item_id,
    UNIFORM(0, 668, RANDOM(22))                        AS day_offset,
    UNIFORM(1, 100, RANDOM(33))                        AS pick,
    UNIFORM(5, 100, RANDOM(44))                        AS qty_pct,
    UNIFORM(90, 115, RANDOM(55))                       AS price_pct,
    UNIFORM(1, 3, RANDOM(66))                          AS plant_no
  FROM TABLE(GENERATOR(ROWCOUNT => 20000))
),
avl_n AS (
  SELECT CATEGORY_CODE, COUNT(*) AS n FROM APPROVED_VENDOR_LIST GROUP BY 1
)
SELECT
  'PO-' || LPAD(g.rn, 6, '0')                                            AS PO_ID,
  DATEADD(day, g.day_offset, '2025-01-01'::DATE)                         AS PO_DATE,
  DECODE(g.plant_no, 1, 'Cikarang Plant', 2, 'Batam Plant', 'Surabaya Plant') AS PLANT,
  a.SUPPLIER_ID,
  i.ITEM_ID,
  GREATEST(1, ROUND(i.MAX_QTY * g.qty_pct / 100))                        AS QUANTITY,
  ROUND(i.BASE_PRICE_USD * g.price_pct / 100, 4)                         AS UNIT_PRICE_USD,
  ROUND(GREATEST(1, ROUND(i.MAX_QTY * g.qty_pct / 100))
        * i.BASE_PRICE_USD * g.price_pct / 100, 2)                       AS AMOUNT_USD
FROM gen g
JOIN ITEMS i ON i.ITEM_ID = g.item_id
JOIN avl_n n ON n.CATEGORY_CODE = i.CATEGORY_CODE
JOIN APPROVED_VENDOR_LIST a
  ON a.CATEGORY_CODE = i.CATEGORY_CODE
 AND a.SEQ = MOD(g.pick, n.n) + 1;

ALTER TABLE PURCHASE_ORDERS ADD PRIMARY KEY (PO_ID);

-- ---------------------------------------------------------------------
-- 5. Unstructured procurement documents (for Cortex Search)
-- ---------------------------------------------------------------------
CREATE OR REPLACE TABLE PROCUREMENT_DOCS (
  DOC_ID STRING PRIMARY KEY,
  TITLE STRING,
  DOC_TYPE STRING,
  CONTENT STRING
);

INSERT INTO PROCUREMENT_DOCS VALUES
('DOC-01','Procurement Policy 2026','policy',
 'All purchases above USD 50,000 require three competitive quotations. Single-source spend in any material category must not exceed 60% of category spend. Exceptions require CPO approval.'),
('DOC-02','Supplier Concentration Guideline','policy',
 'Concentration risk is measured at the level of the ultimate parent company, not the individual legal entity. A supplier group should not represent more than 35% of total direct material spend.'),
('DOC-03','Risk Note: Helix Semiconductor Taiwan lead times','risk_note',
 'Helix Semiconductor Taiwan has extended lead times for microcontrollers and memory to 26 weeks due to foundry allocation. Planners should place orders at least two quarters ahead.'),
('DOC-04','Risk Note: Flood impact at Orion Components Indonesia','risk_note',
 'Orion Components Indonesia (Bekasi) reported flood damage in February 2026. Capacitor and inductor shipments were delayed by three weeks. Recovery completed in April 2026.'),
('DOC-05','Contract Summary: Baja Nusantara Steel','contract',
 'Annual frame agreement for cold rolled coil and aluminium ingot. Price is indexed monthly to the regional steel and LME aluminium index with a 2% cap per month.'),
('DOC-06','Category Strategy: Fasteners','strategy',
 'Fasteners are consolidated with Mitra Fastener Abadi under a vendor-managed inventory programme. Target is 5% cost reduction through standardisation of bolt and nut grades.'),
('DOC-07','Sustainability Requirement: Packaging','policy',
 'From 2026 all corrugated cartons must contain at least 70% recycled fibre and pallets must be heat treated (ISPM-15).'),
('DOC-08','Risk Note: Steel price volatility','risk_note',
 'Regional steel prices rose 12% in Q3 2026. Any material made of steel - coils, fasteners and bearings - is exposed to this increase. Consider hedging or index-linked contracts.');

-- Sanity check
SELECT COUNT(*) AS po_lines, ROUND(SUM(AMOUNT_USD)) AS total_spend_usd,
       MIN(PO_DATE) AS first_po, MAX(PO_DATE) AS last_po
FROM PURCHASE_ORDERS;
