-- binary covariates, 365 days before index
CREATE OR REPLACE TABLE cov_long AS
SELECT DISTINCT c.person_id, 'cond_' || co.condition_concept_id AS covariate
FROM study_cohort c JOIN condition_occurrence co ON co.person_id = c.person_id
WHERE co.condition_start_date BETWEEN c.index_date - 365 AND c.index_date - 1
UNION
SELECT DISTINCT c.person_id, 'drug_' || a.ancestor_concept_id
FROM study_cohort c
JOIN drug_exposure de ON de.person_id = c.person_id
JOIN concept_ancestor a ON a.descendant_concept_id = de.drug_concept_id
JOIN concept ing ON ing.concept_id = a.ancestor_concept_id AND ing.concept_class_id = 'Ingredient'
WHERE de.drug_exposure_start_date BETWEEN c.index_date - 365 AND c.index_date - 1
  AND a.ancestor_concept_id NOT IN (SELECT concept_id FROM codeset_root WHERE set = 'exposure')
UNION
SELECT DISTINCT c.person_id, 'proc_' || po.procedure_concept_id
FROM study_cohort c JOIN procedure_occurrence po ON po.person_id = c.person_id
WHERE po.procedure_date BETWEEN c.index_date - 365 AND c.index_date - 1
UNION
-- pre-specified history: any time before index
SELECT DISTINCT c.person_id, 'hist_' || cs.label
FROM study_cohort c
JOIN condition_occurrence co ON co.person_id = c.person_id
JOIN codeset cs ON cs.concept_id = co.condition_concept_id AND cs.set = 'history'
WHERE co.condition_start_date < c.index_date
UNION
SELECT DISTINCT c.person_id, 'rx_' || cs.label
FROM study_cohort c
JOIN drug_exposure de ON de.person_id = c.person_id
JOIN codeset cs ON cs.concept_id = de.drug_concept_id AND cs.set = 'drug365'
WHERE de.drug_exposure_start_date BETWEEN c.index_date - 365 AND c.index_date - 1;

CREATE OR REPLACE TABLE cov_visits AS
SELECT c.person_id, count(v.visit_occurrence_id) AS n_visits
FROM study_cohort c LEFT JOIN visit_occurrence v ON v.person_id = c.person_id
  AND v.visit_start_date BETWEEN c.index_date - 365 AND c.index_date - 1
GROUP BY 1;

CREATE OR REPLACE TABLE cov_names AS
SELECT DISTINCT l.covariate,
  coalesce(c.concept_name, replace(substr(l.covariate, strpos(l.covariate, '_') + 1), '_', ' ')) AS name
FROM cov_long l
LEFT JOIN concept c ON l.covariate NOT LIKE 'hist_%' AND l.covariate NOT LIKE 'rx_%'
  AND c.concept_id = TRY_CAST(substr(l.covariate, strpos(l.covariate, '_') + 1) AS BIGINT);

-- negative control outcomes
CREATE OR REPLACE TABLE nc_outcome AS
SELECT c.person_id, cs.label,
  max(CASE WHEN co.condition_start_date <= c.index_date THEN 1 ELSE 0 END) AS prior,
  max(CASE WHEN co.condition_start_date BETWEEN c.index_date - 365 AND c.index_date THEN 1 ELSE 0 END) AS prior365,
  min(CASE WHEN co.condition_start_date > c.index_date THEN co.condition_start_date END) AS first_after
FROM study_cohort c
JOIN condition_occurrence co ON co.person_id = c.person_id
JOIN codeset cs ON cs.concept_id = co.condition_concept_id AND cs.set = 'negative_control'
GROUP BY 1, 2;
