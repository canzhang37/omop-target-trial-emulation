-- exposure records of the two study ingredients
CREATE OR REPLACE TABLE exp_rec AS
SELECT de.person_id, cs.label AS arm, de.drug_exposure_start_date AS start_date,
       coalesce(de.drug_exposure_end_date,
                de.drug_exposure_start_date + CAST(coalesce(de.days_supply, 29) AS INTEGER)) AS end_date
FROM drug_exposure de
JOIN codeset cs ON cs.concept_id = de.drug_concept_id AND cs.set = 'exposure';

-- eras: gaps of 30 days or less joined
CREATE OR REPLACE TABLE exp_era AS
WITH o AS (
  SELECT *, max(end_date) OVER (PARTITION BY person_id, arm ORDER BY start_date, end_date
                                ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS prev_end
  FROM exp_rec
), f AS (
  SELECT *, CASE WHEN prev_end IS NULL OR start_date > prev_end + 30 THEN 1 ELSE 0 END AS new_era FROM o
), g AS (
  SELECT *, sum(new_era) OVER (PARTITION BY person_id, arm ORDER BY start_date, end_date
                               ROWS UNBOUNDED PRECEDING) AS era
  FROM f
)
SELECT person_id, arm, era, min(start_date) AS era_start, max(end_date) AS era_end
FROM g GROUP BY 1, 2, 3;

CREATE OR REPLACE TABLE first_use AS
SELECT person_id, arm, min(era_start) AS first_start FROM exp_era GROUP BY 1, 2;

CREATE OR REPLACE TABLE candidate AS
WITH idx AS (SELECT person_id, min(first_start) AS index_date FROM first_use GROUP BY 1)
SELECT i.person_id, i.index_date, min(f.arm) AS arm, count(*) AS n_arms_on_index
FROM idx i JOIN first_use f ON f.person_id = i.person_id AND f.first_start = i.index_date
GROUP BY 1, 2;

CREATE OR REPLACE TABLE eligibility AS
SELECT c.*, p.gender_concept_id,
       year(c.index_date) - p.year_of_birth
         - CASE WHEN month(c.index_date) * 100 + day(c.index_date)
                     < coalesce(p.month_of_birth, 1) * 100 + coalesce(p.day_of_birth, 1) THEN 1 ELSE 0 END AS age,
       op.observation_period_start_date AS obs_start, op.observation_period_end_date AS obs_end,
       op.observation_period_start_date IS NOT NULL AND op.observation_period_start_date <= c.index_date - 365 AS e_obs,
       NOT EXISTS (SELECT 1 FROM exp_rec r WHERE r.person_id = c.person_id AND r.start_date < c.index_date) AS e_new,
       NOT EXISTS (SELECT 1 FROM condition_occurrence co
                   JOIN codeset cs ON cs.concept_id = co.condition_concept_id AND cs.set = 'outcome'
                   WHERE co.person_id = c.person_id AND co.condition_start_date <= c.index_date) AS e_no_prior,
       c.n_arms_on_index = 1 AS e_single
FROM candidate c
JOIN person p ON p.person_id = c.person_id
LEFT JOIN observation_period op ON op.person_id = c.person_id
  AND c.index_date BETWEEN op.observation_period_start_date AND op.observation_period_end_date;

CREATE OR REPLACE TABLE attrition AS
SELECT 1 AS step, 'first exposure to either drug' AS criterion, count(*) AS n,
       count(*) FILTER (WHERE arm = 'celecoxib') AS celecoxib, count(*) FILTER (WHERE arm = 'diclofenac') AS diclofenac
FROM eligibility
UNION ALL
SELECT 2, 'age 18 or older at index', count(*), count(*) FILTER (WHERE arm = 'celecoxib'), count(*) FILTER (WHERE arm = 'diclofenac')
FROM eligibility WHERE age >= 18
UNION ALL
SELECT 3, '365 days of observation before index', count(*), count(*) FILTER (WHERE arm = 'celecoxib'), count(*) FILTER (WHERE arm = 'diclofenac')
FROM eligibility WHERE age >= 18 AND e_obs
UNION ALL
SELECT 4, 'no earlier exposure to either drug', count(*), count(*) FILTER (WHERE arm = 'celecoxib'), count(*) FILTER (WHERE arm = 'diclofenac')
FROM eligibility WHERE age >= 18 AND e_obs AND e_new
UNION ALL
SELECT 5, 'no GI hemorrhage on or before index', count(*), count(*) FILTER (WHERE arm = 'celecoxib'), count(*) FILTER (WHERE arm = 'diclofenac')
FROM eligibility WHERE age >= 18 AND e_obs AND e_new AND e_no_prior
UNION ALL
SELECT 6, 'did not start both drugs on the same day', count(*), count(*) FILTER (WHERE arm = 'celecoxib'), count(*) FILTER (WHERE arm = 'diclofenac')
FROM eligibility WHERE age >= 18 AND e_obs AND e_new AND e_no_prior AND e_single;

CREATE OR REPLACE TABLE study_cohort AS
WITH e AS (
  SELECT * FROM eligibility WHERE age >= 18 AND e_obs AND e_new AND e_no_prior AND e_single
), x AS (
  SELECT e.person_id, e.arm, e.index_date, e.age, e.gender_concept_id, e.obs_end,
    (SELECT max(era_end) FROM exp_era r WHERE r.person_id = e.person_id AND r.arm = e.arm AND r.era_start = e.index_date) AS era_end,
    (SELECT min(start_date) FROM exp_rec r WHERE r.person_id = e.person_id AND r.arm <> e.arm AND r.start_date > e.index_date) AS switch_date,
    (SELECT min(death_date) FROM death d WHERE d.person_id = e.person_id) AS death_date,
    (SELECT min(co.condition_start_date) FROM condition_occurrence co
       JOIN codeset cs ON cs.concept_id = co.condition_concept_id AND cs.set = 'outcome'
       WHERE co.person_id = e.person_id AND co.condition_start_date > e.index_date) AS outcome_date
  FROM e
), t AS (
  SELECT *,
    least(era_end + 30, index_date + 365, obs_end, coalesce(switch_date - 1, DATE '9999-12-31'),
          coalesce(death_date, DATE '9999-12-31')) AS ot_end,
    least(index_date + 365, obs_end, coalesce(death_date, DATE '9999-12-31')) AS itt_end
  FROM x
)
SELECT *,
  outcome_date IS NOT NULL AND outcome_date <= ot_end AS ot_event,
  date_diff('day', index_date, CASE WHEN outcome_date IS NOT NULL AND outcome_date <= ot_end THEN outcome_date ELSE ot_end END) AS ot_days,
  outcome_date IS NOT NULL AND outcome_date <= itt_end AS itt_event,
  date_diff('day', index_date, CASE WHEN outcome_date IS NOT NULL AND outcome_date <= itt_end THEN outcome_date ELSE itt_end END) AS itt_days
FROM t;
