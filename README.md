# Ontology-grounded Cortex Agents on Snowflake — Hands-on Tutorial

> 🇮🇩 Versi Bahasa Indonesia: [README.ind.md](README.ind.md)

Build two Cortex Agents on the **same** synthetic procurement data and compare them:

| Agent | Tools |
|---|---|
| `PROCUREMENT_BASELINE_AGENT` | Cortex Analyst (flat semantic view) + Cortex Search (documents) |
| `PROCUREMENT_ONTOLOGY_AGENT` | Cortex Analyst (**ontology-enriched** semantic view) + Cortex Search (documents) + **Cortex Search over concept profiles (GraphRAG)** + **`ontology_expand` stored procedure (graph traversal)** |

Inspired by the Snowflake Engineering blog
[Ontology-grounded Reasoning with Cortex Agents](https://www.snowflake.com/en/blog/engineering/ontology-grounded-cortex-agents/)
and the reference implementation [Snowflake-Labs/ontology-on-snowflake](https://github.com/Snowflake-Labs/ontology-on-snowflake).

---

## 1. What is an ontology?

An **ontology** is a formal model of a business domain. It declares:

- **Concepts / classes** — `Capacitor`, `Supplier`, `Supplier Group`, `Region`
- **Hierarchies** (`subClassOf`, transitive) — `Ceramic Capacitor ⊂ Capacitor ⊂ Passive Component ⊂ Electronic Component`
- **Typed relationships** — `Supplier —subsidiary_of→ Supplier Group`, `Supplier —located_in→ Country`
- **Synonyms / labels** — `MLCC` = Ceramic Capacitor, `APD` (Bahasa) = PPE, `chip` = Integrated Circuit
- **Composite concepts** — `Steel-Price-Exposed Material` = Steel Coil + Fasteners + Bearings
- **Rules / constraints** — "supplier concentration is measured at the ultimate parent"

A **schema** tells you *where* data is stored. A **semantic view** tells you *what the columns and metrics mean*.
An **ontology** tells you *what the real-world concepts are and how they relate*. That knowledge is usually not in
any table: it lives in SME heads, Excel mappings, or industry standards such as **FIBO, SNOMED CT, ICD-10, GS1,
UNSPSC** (published as OWL / RDF / SKOS).

### Ontology on Snowflake — the 5-layer pattern

```
Layer 5  Cortex Agent             intent routing across tools
Layer 4  Semantic Views           baseline + ontology-enriched (Cortex Analyst)
Layer 3  Reasoning                Recursive-CTE closure, flattened hierarchy, GraphRAG profiles, expand procedure
Layer 2  Ontology metadata        ONT_CLASS, ONT_RELATION_DEF   (meaning declared as data)
Layer 1  Physical graph           KG_NODE (entities) + KG_EDGE (relationships) — plain Snowflake tables
```

**Facts are stored once, meaning is declared as metadata, abstractions are generated.** No separate graph database is
needed. RBAC, masking, lineage, time travel and replication apply to the ontology automatically.

## 2. Why does it matter?

Business users ask in **concepts** ("electronics", "the Orion group", "anything exposed to steel prices"). Data is
stored as **leaf codes** and **legal entities**. Without an ontology, an agent has to *guess* the scope, usually with
`ILIKE '%…%'` or the LLM's general knowledge:

- **Generic hierarchies** (is a connector electronic?) — the LLM may guess right, but not deterministically and with
  no audit trail.
- **Company-specific knowledge** (Kirana Passive Tech is 2 levels below Orion Group; what "steel exposed" means
  here) — the LLM **cannot know**.
- **Local jargon** ("APD", "elko", "baut") — breaks unless every synonym is configured.

Snowflake's biomedical benchmark (22 hard questions × 5 runs) reported:

| Agent architecture | Tools | Accuracy |
|---|---|---|
| Semantic view baseline | 1 | 50.0% |
| + Knowledge graph traversal | 7 | 60.0% |
| + Flattened GraphRAG | 2 | 70.0% |
| + GraphRAG + terminology mapping | 2 | 78.2% |

The blog presents these results as *directional*. Its key lessons: fix the data layer first (pre-computed profiles),
fewer tools can beat more tools, keep hand-curated mappings thin, and iterate with an eval loop.

**Use an ontology when** questions involve deep or changing hierarchies, multi-level ownership, composite concepts,
domain synonyms, or a need for explainable scope. **Analyst + Search is enough when** concepts are already columns,
hierarchies are shallow and stable, or questions are about documents.

---

## 3. The demo scenario

*PT Nusantara Manufaktur* (fictional) buys electronic components, mechanical parts, raw materials, packaging and MRO
supplies from 14 suppliers across ASEAN and East Asia. The ERP stores only:
- the **leaf** category of each item (e.g. `Ceramic Capacitor`) — no hierarchy,
- the **legal entity** of each supplier — no corporate ownership.

The ontology adds a 6-level taxonomy (44 concepts incl. 2 composite concepts), EN + Bahasa synonyms, a 2-level
corporate ownership graph (including an acquisition) and country → region.

```
ontology-tutorial/
├── README.md / README.ind.md
└── sql/
    ├── 00_setup.sql             warehouse, database, schemas
    ├── 01_raw_data.sql          ERP tables + 20,000 synthetic PO lines + 8 procurement documents
    ├── 02_ontology_layer.sql    Layer 1-2: KG_NODE, KG_EDGE, ONT_CLASS, ONT_RELATION_DEF
    ├── 03_reasoning_layer.sql   Layer 3: closure, flattened path, supplier hierarchy, GraphRAG profiles, ONTOLOGY_EXPAND
    ├── 04_semantic_views.sql    Layer 4: baseline SV + ontology SV
    ├── 05_cortex_search.sql     docs search + concept search (GraphRAG)
    ├── 06_agents.sql            Layer 5: baseline agent + ontology agent
    ├── 07_ground_truth.sql      answer key for the demo questions
    ├── 08_compare_agents.sql    ask both agents the same 6 questions
    └── 99_cleanup.sql           drop everything
```

## 4. Prerequisites

- A Snowflake account with **Cortex Analyst, Cortex Search and Cortex Agents** (enable
  `CORTEX_ENABLED_CROSS_REGION` if your region lacks the models).
- A role that can create a warehouse, a database, semantic views, Cortex Search services, procedures and agents
  (the scripts use `ACCOUNTADMIN` for simplicity) and that has `SNOWFLAKE.CORTEX_USER`.
- Snowsight (Workspaces / worksheets), Snowflake CLI (`snow sql -f`) or Cortex Code.

## 5. Step by step

Run the scripts **in order**. Each one is idempotent (`CREATE OR REPLACE`).

### Step 0 — Setup
```sql
-- sql/00_setup.sql
CREATE WAREHOUSE IF NOT EXISTS ONTOLOGY_WH WAREHOUSE_SIZE = XSMALL AUTO_SUSPEND = 60 ...;
CREATE DATABASE IF NOT EXISTS ONTOLOGY_DEMO;
CREATE SCHEMA ... RAW / ONTOLOGY / AGENTS;
```

### Step 1 — Operational data (what the ERP knows)
`sql/01_raw_data.sql` creates `ITEM_CATEGORY` (22 flat leaf categories), `ITEMS` (31 parts whose names do **not**
reveal the hierarchy), `SUPPLIERS` (14, flat), `PURCHASE_ORDERS` (20,000 lines, Jan 2025 – Oct 2026, ~USD 195M) and
`PROCUREMENT_DOCS` (policies, risk notes, contracts).

### Step 2 — Ontology: knowledge graph + metadata (Layers 1–2)
`sql/02_ontology_layer.sql`
```sql
CREATE TABLE KG_NODE (NODE_ID STRING, NODE_TYPE STRING, NAME STRING, PROPS VARIANT, ...);
CREATE TABLE KG_EDGE (EDGE_ID STRING, SRC_ID STRING, DST_ID STRING, EDGE_TYPE STRING,
                      EFFECTIVE_START DATE, EFFECTIVE_END DATE, ...);
-- concepts carry definition, synonyms[] and the ERP category_code (for leaves)
-- edges: SUBCLASS_OF, INCLUDES (composites), SUBSIDIARY_OF, LOCATED_IN, PART_OF_REGION
```
`ONT_CLASS` and `ONT_RELATION_DEF` declare the classes and the relation semantics (domain, range, cardinality,
**transitive**, inverse). To load an industry ontology instead, parse OWL/RDF (e.g. with `rdflib`) into the same two
tables.

### Step 3 — Reasoning layer (Layer 3)
`sql/03_reasoning_layer.sql`

| Object | Purpose |
|---|---|
| `VW_ONT_CONCEPT_CLOSURE` | Recursive CTE: every (descendant, ancestor) pair — the SQL equivalent of `rdfs:subClassOf*` |
| `VW_ONT_CONCEPT_EXPANSION` | Concept / composite → all ERP leaf categories it covers |
| `VW_ONT_CATEGORY_PATH` | One row per leaf with `MATERIAL_TYPE`, `CATEGORY_FAMILY`, `CATEGORY_GROUP`, `CATEGORY_CLASS`, `CATEGORY_PATH`. Safe to join to facts (no fan-out) |
| `VW_ONT_SUPPLIER_HIERARCHY` | Supplier → immediate parent → **ultimate parent** (transitive), country, region |
| `CONCEPT_PROFILE` | **Flattened GraphRAG** document per node: name, synonyms, definition, path, children, covered leaves, member suppliers, `SQL_FILTER_HINT` |
| `ONTOLOGY_EXPAND(term)` | Deterministic agent tool: term or synonym → node → leaves / members / filter hint (JSON) |

```sql
CALL ONTOLOGY_DEMO.ONTOLOGY.ONTOLOGY_EXPAND('steel exposure');
-- → Steel-Price-Exposed Material: Steel Coil, Hex Bolt, Machine Screw, Hex Nut, Ball Bearing
CALL ONTOLOGY_DEMO.ONTOLOGY.ONTOLOGY_EXPAND('Orion');
-- → Orion Electronics Group: Orion Components Indonesia, Orion Semicon Malaysia, Kirana Passive Tech (level 2)
```

> ⚠️ Avoid joining fact tables to a closure table, because one fact row matches many ancestors and gets double
> counted. Use a flattened 1-row-per-leaf view or `IN (...)` filters, as done here.

### Step 4 — Semantic views (Layer 4)
`sql/04_semantic_views.sql` creates two semantic views over the same facts:
- `PROCUREMENT_BASELINE_SV`: ERP semantics only (`CATEGORY_NAME`, `SUPPLIER_NAME`, `COUNTRY_CODE`).
- `PROCUREMENT_ONTOLOGY_SV`: adds ontology-derived dimensions (`MATERIAL_TYPE`, `CATEGORY_FAMILY`, `CATEGORY_GROUP`,
  `CATEGORY_CLASS`, `CATEGORY_PATH`, `IMMEDIATE_PARENT`, `ULTIMATE_PARENT`, `SOURCING_REGION`).

### Step 5 — Cortex Search
`sql/05_cortex_search.sql`
- `PROCUREMENT_DOCS_SEARCH`: policies / risk notes / contracts (used by both agents).
- `CONCEPT_SEARCH`: the GraphRAG index over `CONCEPT_PROFILE.PROFILE_TEXT`. It resolves fuzzy or Bahasa wording
  (e.g. *"komponen pasif untuk PCB"* → `Passive Component`).

### Step 6 — Agents (Layer 5)
`sql/06_agents.sql`. The ontology agent's orchestration instruction enforces **grounding first**:
1. `ontology_expand(term)` → if no match → `concept_search` → `ontology_expand(best NAME)`
2. `procurement_analyst` with the **explicit** filter from `sql_filter_hint`
3. `procurement_docs` for policy thresholds and risk notes
4. Always state the resolved concept and the included leaves or members (audit trail)

The custom tool is wired as a `generic` tool backed by a stored procedure:
```yaml
tools:
  - tool_spec:
      type: "generic"
      name: "ontology_expand"
      input_schema: { type: object, properties: { term: { type: string } }, required: ["term"] }
tool_resources:
  ontology_expand:
    type: "procedure"
    identifier: "ONTOLOGY_DEMO.ONTOLOGY.ONTOLOGY_EXPAND"
    execution_environment: { type: warehouse, warehouse: "ONTOLOGY_WH" }
```

### Step 7 — Ground truth
`sql/07_ground_truth.sql` computes the correct answers deterministically (view `DEMO_GROUND_TRUTH`).

### Step 8 — Compare the agents
`sql/08_compare_agents.sql` asks both agents the same 6 questions via `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` and stores the
responses in `AGENT_COMPARISON` (summary view `AGENT_COMPARISON_SUMMARY`). You can also chat with both agents in
**Snowflake Intelligence / CoWork** or in Snowsight → *AI & ML → Agents*.

| # | Question | What it tests |
|---|---|---|
| Q1 | Total spend on electronic components in 2026? | Hierarchy roll-up (generic knowledge may guess it) |
| Q2 | Spend on capacitors in 2026? | Mid-level concept |
| Q3 | Spend with the Orion group incl. all subsidiaries? | **Company-specific** multi-level ownership |
| Q4 | 2026 spend on material exposed to the steel price? | **Composite concept** across branches |
| Q5 | *Berapa total pembelian APD tahun 2026?* | Bahasa synonym |
| Q6 | Does any supplier group breach the concentration policy? | Ontology (ultimate parent) + document (35% threshold) |

Expected answers (from `07_ground_truth.sql`):

| # | Correct answer |
|---|---|
| Q1 | $45.03M (11 leaf categories) |
| Q2 | $2.47M (ceramic + electrolytic) |
| Q3 | $27.74M (3 entities, incl. Kirana Passive Tech at level 2) |
| Q4 | $13.06M (steel coil + bolts + screws + nuts + ball bearings) |
| Q5 | $2.41M |
| Q6 | No breach. Largest group is Helix Semiconductor Holdings at 34.1% of direct spend (limit 35%) |

#### Observed results (one validated run)

| # | Baseline agent | Ontology agent |
|---|---|---|
| Q1 | ✅ $45.0M, but unsure: called Connector/Relay "borderline" and offered an alternative $39.1M | ✅ $45.0M, concept path + 11 leaves listed |
| Q2 | ✅ $2.47M | ✅ $2.47M + concept path |
| Q3 | ❌ **$25.1M**: matched on the name "Orion", said it cannot know the ownership, missed Kirana Passive Tech | ✅ **$27.7M**, incl. Kirana Passive Tech (level 2), explained why name matching would miss it |
| Q4 | ✅ $13.06M, found the definition in the steel risk note (DOC-08) | ✅ $13.06M via the composite concept |
| Q5 | ✅ $2.41M (APD = PPE is general knowledge) | ✅ $2.41M + synonym trail |
| Q6 | ⚠️ "No breach", but named **Baja (22–24%)** as largest group, treated Helix and Nova Chip as separate, and the direct-material base changed between runs | ✅ Helix Semiconductor Holdings (incl. Nova Chip) **34.1%**, just under 35%, so recommends close monitoring |

**Lessons that are useful in a customer conversation:**
- Where the knowledge is **general** (electronics, capacitors, APD), a modern LLM often guesses right. The ontology
  adds **determinism, consistency and an audit trail**, not just accuracy.
- Where the knowledge is **company-specific** (ownership, acquisitions), the baseline **cannot** get it right, and
  this is where the ontology pays off.
- When a definition exists **in a document** (Q4), Cortex Search can act as a "light ontology". Writing definitions
  down is the first step toward a real ontology.
- LLM answers vary between runs. Run each question several times, as in the blog's 5-run methodology.

#### Bonus: agility test (a new acquisition without touching the agent)
```sql
INSERT INTO ONTOLOGY_DEMO.ONTOLOGY.KG_EDGE (EDGE_ID, SRC_ID, DST_ID, EDGE_TYPE, PROPS, EFFECTIVE_START)
SELECT 'E:OWN:S:112', 'S:112', 'G:HELIX', 'SUBSIDIARY_OF', OBJECT_CONSTRUCT('ownership_pct', 100), CURRENT_DATE();
-- re-run sql/03_reasoning_layer.sql and sql/05_cortex_search.sql, then ask Q6 again
```
Tested result: Helix rises to ~39.5% and the agent reports a **breach**, with no change to the semantic view or the
agent. Revert with `DELETE FROM ONTOLOGY_DEMO.ONTOLOGY.KG_EDGE WHERE EDGE_ID = 'E:OWN:S:112';` and re-run 03 and 05.

### Step 9 — Clean up
```sql
-- sql/99_cleanup.sql
DROP DATABASE IF EXISTS ONTOLOGY_DEMO;
DROP WAREHOUSE IF EXISTS ONTOLOGY_WH;
```

---

## 6. Taking this to production

1. **Golden set first.** Collect 20–50 real questions with correct answers and evaluate the baseline agent, so you
   know where it fails.
2. **Source the ontology.** Use an industry standard (FIBO, SNOMED, GS1, UNSPSC; check licences) or an internal
   taxonomy/MDM, and load it into `KG_NODE` / `KG_EDGE`.
3. **Map facts to concepts.** Measure coverage (share of spend or rows mapped to a node).
4. **Keep the tool surface small.** One expand tool + one concept search + Analyst + docs search.
5. **Automate refresh.** Rebuild `CONCEPT_PROFILE` / flattened views with a task or Dynamic Table when the ontology
   changes. Cortex Search follows via `TARGET_LAG`.
6. **Model time.** Use `EFFECTIVE_START/END` on edges for acquisitions and re-classifications.
7. **Iterate with evaluations.** Use Cortex Agent evaluations (`EXECUTE_AI_EVALUATION`) and Cortex Code's
   agent-optimization skill to tune instructions and tool descriptions.
8. **Govern.** Assign a data steward and change process for the ontology, and apply RBAC/masking like any other
   table.

## 7. References

- [Ontology-grounded Reasoning with Cortex Agents](https://www.snowflake.com/en/blog/engineering/ontology-grounded-cortex-agents/) — Snowflake Engineering Blog
- [Ontology on Snowflake — Part 1: Overview & Data Model](https://medium.com/snowflake/ontology-on-snowflake-part-1-overview-and-data-model-9e8eeaac7363)
- [Snowflake-Labs/ontology-on-snowflake](https://github.com/Snowflake-Labs/ontology-on-snowflake)
- Docs: [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents) ·
  [Semantic Views](https://docs.snowflake.com/en/user-guide/views-semantic/overview) ·
  [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview) ·
  [Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)

> All data in this repository is synthetic. Company and supplier names are fictional.
