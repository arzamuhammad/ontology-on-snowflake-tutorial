-- =====================================================================
-- 08_compare_agents.sql — Ask BOTH agents the same 6 questions, side by side
-- Compare the answers with 07_ground_truth.sql.
-- Each call takes ~20-60 s. (DATA_AGENT_RUN needs constant arguments, hence one call per row.)
-- =====================================================================
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE ONTOLOGY_WH;

CREATE OR REPLACE TABLE ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (
  Q STRING, AGENT STRING, QUESTION STRING, RESPONSE VARIANT, RUN_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q1', 'baseline', 'What is our total spend on electronic components in 2026?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"What is our total spend on electronic components in 2026?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q1', 'ontology', 'What is our total spend on electronic components in 2026?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"What is our total spend on electronic components in 2026?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q2', 'baseline', 'How much did we spend on capacitors in 2026?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"How much did we spend on capacitors in 2026?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q2', 'ontology', 'How much did we spend on capacitors in 2026?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"How much did we spend on capacitors in 2026?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q3', 'baseline', 'How much did we spend in total with the Orion group, including all its subsidiaries?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"How much did we spend in total with the Orion group, including all its subsidiaries?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q3', 'ontology', 'How much did we spend in total with the Orion group, including all its subsidiaries?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"How much did we spend in total with the Orion group, including all its subsidiaries?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q4', 'baseline', 'What was our 2026 spend on material that is exposed to the steel price?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"What was our 2026 spend on material that is exposed to the steel price?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q4', 'ontology', 'What was our 2026 spend on material that is exposed to the steel price?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"What was our 2026 spend on material that is exposed to the steel price?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q5', 'baseline', 'Berapa total pembelian APD tahun 2026?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"Berapa total pembelian APD tahun 2026?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q5', 'ontology', 'Berapa total pembelian APD tahun 2026?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"Berapa total pembelian APD tahun 2026?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q6', 'baseline', 'In 2026, does any supplier group breach our supplier concentration policy for direct material?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_BASELINE_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"In 2026, does any supplier group breach our supplier concentration policy for direct material?"}]}],"stream":false}$$));

INSERT INTO ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON (Q, AGENT, QUESTION, RESPONSE)
SELECT 'Q6', 'ontology', 'In 2026, does any supplier group breach our supplier concentration policy for direct material?',
       TRY_PARSE_JSON(SNOWFLAKE.CORTEX.DATA_AGENT_RUN('ONTOLOGY_DEMO.AGENTS.PROCUREMENT_ONTOLOGY_AGENT', $${"messages":[{"role":"user","content":[{"type":"text","text":"In 2026, does any supplier group breach our supplier concentration policy for direct material?"}]}],"stream":false}$$));

-- Final answer + tools used, per question and agent
CREATE OR REPLACE VIEW ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON_SUMMARY AS
SELECT
  c.Q, c.AGENT, c.QUESTION,
  ARRAY_TO_STRING(ARRAY_AGG(DISTINCT t.value:tool_use:name::STRING), ', ') AS TOOLS_USED,
  MAX_BY(t.value:text::STRING, IFF(t.value:type::STRING = 'text', t.index, -1)) AS FINAL_ANSWER
FROM ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON c,
     LATERAL FLATTEN(c.RESPONSE:content) t
GROUP BY 1, 2, 3;

SELECT s.Q, s.AGENT, s.TOOLS_USED, g.ANSWER_USD AS GROUND_TRUTH, s.FINAL_ANSWER
FROM ONTOLOGY_DEMO.AGENTS.AGENT_COMPARISON_SUMMARY s
LEFT JOIN ONTOLOGY_DEMO.AGENTS.DEMO_GROUND_TRUTH g ON g.Q = s.Q
ORDER BY s.Q, s.AGENT;
