# Cortex Agent Berbasis Ontology di Snowflake — Tutorial Hands-on

> 🇬🇧 English version: [README.md](README.md)

Tutorial ini membangun dua Cortex Agent di atas data procurement sintetis yang **sama**, lalu membandingkannya:

| Agent | Tool |
|---|---|
| `PROCUREMENT_BASELINE_AGENT` | Cortex Analyst (semantic view datar) + Cortex Search (dokumen) |
| `PROCUREMENT_ONTOLOGY_AGENT` | Cortex Analyst (semantic view **diperkaya ontology**) + Cortex Search (dokumen) + **Cortex Search atas profil konsep (GraphRAG)** + **stored procedure `ontology_expand` (traversal graph)** |

Terinspirasi dari blog Snowflake Engineering
[Ontology-grounded Reasoning with Cortex Agents](https://www.snowflake.com/en/blog/engineering/ontology-grounded-cortex-agents/)
dan implementasi referensi [Snowflake-Labs/ontology-on-snowflake](https://github.com/Snowflake-Labs/ontology-on-snowflake).

---

## 1. Apa itu ontology?

**Ontology** adalah model formal sebuah domain bisnis. Ontology mendefinisikan:

- **Konsep / class**: `Capacitor`, `Supplier`, `Supplier Group`, `Region`
- **Hierarki** (`subClassOf`, transitif): `Ceramic Capacitor ⊂ Capacitor ⊂ Passive Component ⊂ Electronic Component`
- **Relasi bertipe**: `Supplier —subsidiary_of→ Supplier Group`, `Supplier —located_in→ Country`
- **Sinonim / label**: `MLCC` = Ceramic Capacitor, `APD` = PPE, `chip` = Integrated Circuit
- **Konsep komposit**: `Steel-Price-Exposed Material` = Steel Coil + Fastener + Bearing
- **Aturan / constraint**: "konsentrasi supplier diukur di level ultimate parent"

**Skema** menjawab *di mana* data disimpan. **Semantic view** menjawab *apa arti kolom & metrik*. **Ontology**
menjawab *apa konsep dunia nyata dan bagaimana hubungannya*. Pengetahuan ini biasanya tidak ada di tabel mana pun:
ia tersimpan di kepala SME, di file Excel mapping, atau di standar industri seperti **FIBO, SNOMED CT, ICD-10, GS1,
UNSPSC** (format OWL / RDF / SKOS).

### Pola Ontology on Snowflake — 5 lapis

```
Layer 5  Cortex Agent             routing intent antar tool
Layer 4  Semantic Views           baseline + diperkaya ontology (Cortex Analyst)
Layer 3  Reasoning                closure Recursive CTE, hierarki flattened, profil GraphRAG, procedure expand
Layer 2  Metadata ontology        ONT_CLASS, ONT_RELATION_DEF   (makna dideklarasikan sebagai data)
Layer 1  Graph fisik              KG_NODE (entitas) + KG_EDGE (relasi), berupa tabel Snowflake biasa
```

**Fakta disimpan sekali, makna dideklarasikan sebagai metadata, abstraksi di-generate.** Tidak perlu graph database
terpisah. RBAC, masking, lineage, time travel, dan replication otomatis berlaku untuk ontology.

## 2. Mengapa ontology penting?

User bisnis bertanya dengan **konsep** ("elektronik", "grup Orion", "material yang terpengaruh harga baja"), sedangkan
data tersimpan sebagai **kode leaf** dan **entitas legal**. Tanpa ontology, agent harus *menebak* cakupannya, biasanya
dengan `ILIKE '%…%'` atau pengetahuan umum LLM:

- **Hierarki umum** (apakah connector termasuk elektronik?): LLM mungkin benar, tapi tidak deterministik dan tanpa
  audit trail.
- **Pengetahuan khusus perusahaan** (Kirana Passive Tech adalah cucu perusahaan Orion Group; arti "terekspos baja"
  di perusahaan ini): LLM **tidak mungkin tahu**.
- **Jargon lokal** ("APD", "elko", "baut"): gagal kecuali setiap sinonim dikonfigurasi.

Benchmark biomedis Snowflake (22 pertanyaan sulit × 5 run):

| Arsitektur agent | Tool | Akurasi |
|---|---|---|
| Baseline semantic view | 1 | 50,0% |
| + Traversal knowledge graph | 7 | 60,0% |
| + Flattened GraphRAG | 2 | 70,0% |
| + GraphRAG + terminology mapping | 2 | 78,2% |

Blog menyebut hasil ini *direksional*. Pelajaran utamanya: perbaiki lapisan data dulu (profil yang di-precompute),
tool sedikit bisa mengalahkan tool banyak, mapping manual harus tetap tipis, dan iterasi dengan loop evaluasi.

**Gunakan ontology bila** pertanyaan melibatkan hierarki yang dalam/berubah, kepemilikan multi-level, konsep komposit,
sinonim domain, atau butuh cakupan yang bisa dijelaskan. **Analyst + Search sudah cukup bila** konsep sudah berupa
kolom, hierarki dangkal & stabil, atau pertanyaan seputar dokumen.

---

## 3. Skenario demo

*PT Nusantara Manufaktur* (fiktif) membeli komponen elektronik, komponen mekanik, bahan baku, kemasan, dan MRO dari 14
supplier di ASEAN & Asia Timur. ERP hanya menyimpan:
- **kategori leaf** setiap item (mis. `Ceramic Capacitor`), tanpa hierarki;
- **entitas legal** setiap supplier, tanpa struktur kepemilikan.

Ontology menambahkan taksonomi 6 level (44 konsep termasuk 2 konsep komposit), sinonim EN + Bahasa, graph kepemilikan
2 level (termasuk 1 akuisisi), dan negara → region.

```
ontology-tutorial/
├── README.md / README.ind.md
└── sql/
    ├── 00_setup.sql             warehouse, database, schema
    ├── 01_raw_data.sql          tabel ERP + 20.000 baris PO sintetis + 8 dokumen procurement
    ├── 02_ontology_layer.sql    Layer 1-2: KG_NODE, KG_EDGE, ONT_CLASS, ONT_RELATION_DEF
    ├── 03_reasoning_layer.sql   Layer 3: closure, flattened path, hierarki supplier, profil GraphRAG, ONTOLOGY_EXPAND
    ├── 04_semantic_views.sql    Layer 4: SV baseline + SV ontology
    ├── 05_cortex_search.sql     docs search + concept search (GraphRAG)
    ├── 06_agents.sql            Layer 5: baseline agent + ontology agent
    ├── 07_ground_truth.sql      kunci jawaban pertanyaan demo
    ├── 08_compare_agents.sql    tanya kedua agent 6 pertanyaan yang sama
    └── 99_cleanup.sql           hapus semua objek
```

## 4. Prasyarat

- Akun Snowflake dengan **Cortex Analyst, Cortex Search, dan Cortex Agents** (aktifkan
  `CORTEX_ENABLED_CROSS_REGION` bila model belum tersedia di region Anda).
- Role yang bisa membuat warehouse, database, semantic view, Cortex Search service, procedure, dan agent (script
  memakai `ACCOUNTADMIN` agar sederhana) serta memiliki `SNOWFLAKE.CORTEX_USER`.
- Snowsight (Workspaces / worksheet), Snowflake CLI (`snow sql -f`), atau Cortex Code.

## 5. Langkah demi langkah

Jalankan script **berurutan**. Semuanya idempotent (`CREATE OR REPLACE`).

### Langkah 0 — Setup
`sql/00_setup.sql` membuat warehouse `ONTOLOGY_WH` (XS), database `ONTOLOGY_DEMO`, dan schema `RAW` / `ONTOLOGY` /
`AGENTS`.

### Langkah 1 — Data operasional (yang diketahui ERP)
`sql/01_raw_data.sql` membuat `ITEM_CATEGORY` (22 kategori leaf datar), `ITEMS` (31 part yang namanya **tidak**
menyebut hierarki), `SUPPLIERS` (14, datar), `PURCHASE_ORDERS` (20.000 baris, Jan 2025 – Okt 2026, ±USD 195M), dan
`PROCUREMENT_DOCS` (kebijakan, risk note, kontrak).

### Langkah 2 — Ontology: knowledge graph + metadata (Layer 1–2)
`sql/02_ontology_layer.sql`
```sql
CREATE TABLE KG_NODE (NODE_ID STRING, NODE_TYPE STRING, NAME STRING, PROPS VARIANT, ...);
CREATE TABLE KG_EDGE (EDGE_ID STRING, SRC_ID STRING, DST_ID STRING, EDGE_TYPE STRING,
                      EFFECTIVE_START DATE, EFFECTIVE_END DATE, ...);
-- konsep menyimpan definition, synonyms[] dan category_code ERP (untuk leaf)
-- edge: SUBCLASS_OF, INCLUDES (komposit), SUBSIDIARY_OF, LOCATED_IN, PART_OF_REGION
```
`ONT_CLASS` dan `ONT_RELATION_DEF` mendeklarasikan class dan semantik relasi (domain, range, kardinalitas,
**transitif**, inverse). Untuk memakai ontology industri, parse OWL/RDF (mis. dengan `rdflib`) ke dua tabel yang sama.

### Langkah 3 — Reasoning layer (Layer 3)
`sql/03_reasoning_layer.sql`

| Objek | Fungsi |
|---|---|
| `VW_ONT_CONCEPT_CLOSURE` | Recursive CTE: semua pasangan (descendant, ancestor), padanan SQL untuk `rdfs:subClassOf*` |
| `VW_ONT_CONCEPT_EXPANSION` | Konsep / komposit → semua kategori leaf ERP yang dicakup |
| `VW_ONT_CATEGORY_PATH` | 1 baris per leaf: `MATERIAL_TYPE`, `CATEGORY_FAMILY`, `CATEGORY_GROUP`, `CATEGORY_CLASS`, `CATEGORY_PATH`. Aman di-join ke fakta (tanpa fan-out) |
| `VW_ONT_SUPPLIER_HIERARCHY` | Supplier → immediate parent → **ultimate parent** (transitif), negara, region |
| `CONCEPT_PROFILE` | Dokumen **flattened GraphRAG** per node: nama, sinonim, definisi, path, anak, leaf yang dicakup, anggota grup, `SQL_FILTER_HINT` |
| `ONTOLOGY_EXPAND(term)` | Tool agent deterministik: istilah/sinonim → node → leaf / anggota / filter hint (JSON) |

```sql
CALL ONTOLOGY_DEMO.ONTOLOGY.ONTOLOGY_EXPAND('steel exposure');
-- → Steel-Price-Exposed Material: Steel Coil, Hex Bolt, Machine Screw, Hex Nut, Ball Bearing
CALL ONTOLOGY_DEMO.ONTOLOGY.ONTOLOGY_EXPAND('Orion');
-- → Orion Electronics Group: Orion Components Indonesia, Orion Semicon Malaysia, Kirana Passive Tech (level 2)
```

> ⚠️ Jangan join tabel fakta ke tabel closure, karena satu baris fakta akan cocok dengan banyak ancestor dan terhitung
> ganda. Gunakan view flattened (1 baris per leaf) atau filter `IN (...)` seperti di tutorial ini.

### Langkah 4 — Semantic views (Layer 4)
`sql/04_semantic_views.sql` membuat dua semantic view atas fakta yang sama:
- `PROCUREMENT_BASELINE_SV`: hanya semantik ERP (`CATEGORY_NAME`, `SUPPLIER_NAME`, `COUNTRY_CODE`).
- `PROCUREMENT_ONTOLOGY_SV`: menambah dimensi dari ontology (`MATERIAL_TYPE`, `CATEGORY_FAMILY`, `CATEGORY_GROUP`,
  `CATEGORY_CLASS`, `CATEGORY_PATH`, `IMMEDIATE_PARENT`, `ULTIMATE_PARENT`, `SOURCING_REGION`).

### Langkah 5 — Cortex Search
`sql/05_cortex_search.sql`
- `PROCUREMENT_DOCS_SEARCH`: kebijakan / risk note / kontrak (dipakai kedua agent).
- `CONCEPT_SEARCH`: index GraphRAG atas `CONCEPT_PROFILE.PROFILE_TEXT`. Index ini menerjemahkan kata-kata kabur atau
  berbahasa Indonesia (mis. *"komponen pasif untuk PCB"* → `Passive Component`).

### Langkah 6 — Agent (Layer 5)
`sql/06_agents.sql`. Instruksi orkestrasi ontology agent mewajibkan **grounding first**:
1. `ontology_expand(term)` → bila tidak cocok → `concept_search` → `ontology_expand(NAME terbaik)`
2. `procurement_analyst` dengan filter **eksplisit** dari `sql_filter_hint`
3. `procurement_docs` untuk batas kebijakan dan risk note
4. Selalu sebutkan konsep yang dipakai serta leaf/anggota yang dicakup (audit trail)

Tool custom dipasang sebagai tool `generic` yang di-backup stored procedure:
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

### Langkah 7 — Kunci jawaban
`sql/07_ground_truth.sql` menghitung jawaban benar secara deterministik (view `DEMO_GROUND_TRUTH`).

### Langkah 8 — Bandingkan kedua agent
`sql/08_compare_agents.sql` mengirim 6 pertanyaan yang sama ke kedua agent via `SNOWFLAKE.CORTEX.DATA_AGENT_RUN` dan
menyimpan respons di `AGENT_COMPARISON` (ringkasan di view `AGENT_COMPARISON_SUMMARY`). Anda juga bisa chat dengan
kedua agent di **Snowflake Intelligence / CoWork** atau di Snowsight → *AI & ML → Agents*.

| # | Pertanyaan | Yang diuji | Jawaban benar |
|---|---|---|---|
| Q1 | Total spend komponen elektronik 2026? | Roll-up hierarki | $45,03M |
| Q2 | Spend kapasitor 2026? | Konsep level menengah | $2,47M |
| Q3 | Spend grup Orion termasuk semua anak usaha? | Kepemilikan multi-level **khusus perusahaan** | $27,74M |
| Q4 | Spend 2026 untuk material yang terekspos harga baja? | **Konsep komposit** lintas cabang | $13,06M |
| Q5 | *Berapa total pembelian APD tahun 2026?* | Sinonim Bahasa | $2,41M |
| Q6 | Apakah ada grup supplier yang melanggar kebijakan konsentrasi? | Ontology (ultimate parent) + dokumen (batas 35%) | Tidak; terbesar Helix 34,1% |

#### Hasil pengamatan (satu run tervalidasi)

| # | Baseline agent | Ontology agent |
|---|---|---|
| Q1 | ✅ $45,0M, tapi ragu: Connector/Relay disebut "borderline", menawarkan alternatif $39,1M | ✅ $45,0M, path konsep + 11 leaf |
| Q2 | ✅ $2,47M | ✅ $2,47M + path konsep |
| Q3 | ❌ **$25,1M**: hanya mencocokkan nama "Orion", mengaku tidak tahu kepemilikan, melewatkan Kirana Passive Tech | ✅ **$27,7M**, termasuk Kirana Passive Tech (level 2) |
| Q4 | ✅ $13,06M, menemukan definisi di risk note (DOC-08) | ✅ $13,06M via konsep komposit |
| Q5 | ✅ $2,41M (APD = PPE adalah pengetahuan umum) | ✅ $2,41M + jejak sinonim |
| Q6 | ⚠️ "Tidak melanggar", tapi menyebut **Baja (22–24%)** sebagai grup terbesar; Helix & Nova Chip dianggap terpisah; basis direct material berubah antar-run | ✅ Helix Semiconductor Holdings (termasuk Nova Chip) **34,1%**, mendekati 35%, sehingga disarankan monitoring |

**Pelajaran untuk diskusi dengan customer:**
- Untuk pengetahuan **umum** (elektronik, kapasitor, APD), LLM modern sering menebak benar. Ontology menambah
  **determinisme, konsistensi, dan audit trail**.
- Untuk pengetahuan **khusus perusahaan** (kepemilikan, akuisisi), baseline **tidak mungkin** benar. Di sinilah
  ontology paling bernilai.
- Bila definisi tertulis **di dokumen** (Q4), Cortex Search dapat berperan sebagai "ontology ringan". Menuliskan
  definisi adalah langkah pertama menuju ontology.
- Jawaban LLM bervariasi antar-run. Jalankan tiap pertanyaan beberapa kali, seperti metodologi 5-run di blog.

#### Bonus: uji agility (akuisisi baru tanpa mengubah agent)
```sql
INSERT INTO ONTOLOGY_DEMO.ONTOLOGY.KG_EDGE (EDGE_ID, SRC_ID, DST_ID, EDGE_TYPE, PROPS, EFFECTIVE_START)
SELECT 'E:OWN:S:112', 'S:112', 'G:HELIX', 'SUBSIDIARY_OF', OBJECT_CONSTRUCT('ownership_pct', 100), CURRENT_DATE();
-- jalankan ulang sql/03_reasoning_layer.sql dan sql/05_cortex_search.sql, lalu tanya ulang Q6
```
Hasil uji: Helix menjadi ±39,5% dan agent melaporkan **pelanggaran**, tanpa mengubah semantic view ataupun agent.
Kembalikan dengan `DELETE FROM ONTOLOGY_DEMO.ONTOLOGY.KG_EDGE WHERE EDGE_ID = 'E:OWN:S:112';` lalu jalankan ulang 03
dan 05.

### Langkah 9 — Cleanup
```sql
-- sql/99_cleanup.sql
DROP DATABASE IF EXISTS ONTOLOGY_DEMO;
DROP WAREHOUSE IF EXISTS ONTOLOGY_WH;
```

---

## 6. Membawa ke production

1. **Golden set dulu.** Kumpulkan 20–50 pertanyaan nyata beserta jawaban benarnya, lalu evaluasi baseline agent agar
   tahu di mana ia gagal.
2. **Sumber ontology.** Gunakan standar industri (FIBO, SNOMED, GS1, UNSPSC; cek lisensi) atau taksonomi
   internal/MDM, lalu load ke `KG_NODE` / `KG_EDGE`.
3. **Mapping fakta ke konsep.** Ukur coverage (porsi spend/baris yang ter-mapping ke node).
4. **Tool seminimal mungkin.** Satu tool expand + satu concept search + Analyst + docs search.
5. **Otomatiskan refresh.** Rebuild `CONCEPT_PROFILE` / view flattened dengan task atau Dynamic Table saat ontology
   berubah. Cortex Search mengikuti via `TARGET_LAG`.
6. **Modelkan waktu.** Gunakan `EFFECTIVE_START/END` di edge untuk akuisisi dan reklasifikasi.
7. **Iterasi dengan evaluasi.** Gunakan Cortex Agent evaluations (`EXECUTE_AI_EVALUATION`) dan skill
   agent-optimization di Cortex Code untuk menyempurnakan instruksi & deskripsi tool.
8. **Governance.** Tetapkan data steward dan proses perubahan ontology, serta terapkan RBAC/masking seperti tabel
   lainnya.

## 7. Referensi

- [Ontology-grounded Reasoning with Cortex Agents](https://www.snowflake.com/en/blog/engineering/ontology-grounded-cortex-agents/) — Snowflake Engineering Blog
- [Ontology on Snowflake — Part 1: Overview & Data Model](https://medium.com/snowflake/ontology-on-snowflake-part-1-overview-and-data-model-9e8eeaac7363)
- [Snowflake-Labs/ontology-on-snowflake](https://github.com/Snowflake-Labs/ontology-on-snowflake)
- Dokumentasi: [Cortex Agents](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-agents) ·
  [Semantic Views](https://docs.snowflake.com/en/user-guide/views-semantic/overview) ·
  [Cortex Search](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-overview) ·
  [Cortex Analyst](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-analyst)

> Seluruh data di repository ini sintetis. Nama perusahaan dan supplier adalah fiktif.
