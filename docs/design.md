# Design: new users of celecoxib vs diclofenac and gastrointestinal bleeding

Written before the data were downloaded. Changes after that point go under Amendments at the end, with the reason.

## Question

Among adults who start celecoxib or diclofenac, is the risk of gastrointestinal (GI) hemorrhage during treatment lower with celecoxib? Trials and observational studies of selective COX-2 inhibitors point that way. The data here are synthetic, so the answer is a test of the pipeline, not evidence about the drugs.

## Data

Eunomia GiBleed, OMOP CDM v5.3 (OHDSI EunomiaDatasets, Apache 2.0): simulated patient records with a subset of the OMOP standardized vocabularies, distributed for testing and teaching. The CSV files are loaded into DuckDB, and every cohort, outcome and covariate is built with SQL on the CDM tables.

## Target trial and its emulation

| Element | Target trial | Emulation |
|---|---|---|
| Eligibility | Adults 18 or older, no use of either drug in the past, no GI hemorrhage in the past, at least 365 days of history | First drug_exposure of either ingredient is the index date. Age 18 or older at index, at least 365 days of observation before index, no prior exposure to either ingredient, no GI hemorrhage condition on or before index, not starting both on the same day |
| Strategies | Start celecoxib, or start diclofenac | Ingredient of the first exposure (descendants of the RxNorm ingredient concept) |
| Assignment | Randomized | Propensity score matching on baseline covariates |
| Outcome | First GI hemorrhage | First condition_occurrence of the GI hemorrhage concept or its descendants after index |
| Follow-up | From day 1 after the start until the outcome, the end of treatment, death or 365 days | On-treatment: day 1 to the end of continuous exposure plus a 30-day grace period, capped at 365 days, censored at the end of the observation period or death |
| Causal contrast | Per-protocol effect while on the assigned drug | On-treatment hazard ratio in the matched cohort |

Concepts expected from the Eunomia documentation, checked by name after loading: celecoxib 1118084, diclofenac 1124300 (RxNorm ingredients), gastrointestinal hemorrhage 192671 (SNOMED).

Continuous exposure: drug_exposure records of the index ingredient are joined into one era when the gap between the end of one record and the start of the next is 30 days or less. A missing drug_exposure_end_date is taken as the start date plus days_supply, or the start date plus 29 days when days_supply is also missing.

## Code sets

Every concept set is written to `codesets/` as a CSV (concept_id, concept_name, vocabulary, domain, role) and resolved through concept_ancestor, so descendants are included. Covariates are built from the standard concepts. Where the bundled vocabulary contains source codes that map to a concept set (concept_relationship "Maps to"), they are listed next to it.

## Covariates

Measured in the 365 days before index, index day excluded, unless noted.

Pre-specified: age at index, sex, index year, number of visits; any history before index of osteoarthritis, rheumatoid arthritis, hypertension, diabetes, chronic kidney disease, coronary heart disease, heart failure, atrial fibrillation and peptic ulcer; drug use of anticoagulants (warfarin and direct oral anticoagulants), antiplatelets (aspirin, clopidogrel), systemic corticosteroids, proton pump inhibitors and SSRIs.

Data-driven: every condition, drug ingredient and procedure concept recorded for at least 1% of the eligible patients in the window, excluding the two study ingredients.

A pre-specified covariate recorded for fewer than 10 patients is reported but left out of the model.

## Propensity score

L1-penalized logistic regression (glmnet, lambda chosen by 10-fold cross-validation) on all covariates, with the pre-specified covariates unpenalized. Matching is 1:1 nearest neighbor without replacement on the logit of the score, with a caliper of 0.2 standard deviations of the logit, in random order with a fixed seed.

## Analysis

Primary: Cox model of the on-treatment outcome on treatment in the matched cohort, with a robust variance clustered on matched pairs. Reported with the 95% CI, the number of events and person-years in each arm, and the E-value for the estimate and for the CI limit closest to 1.

Sensitivity:
1. Intention-to-treat time at risk: day 1 to 365 days, censored at the end of observation or death.
2. Inverse probability of treatment weighting (ATE, stabilized, weights truncated at the 1st and 99th percentiles) instead of matching.
3. Unadjusted estimate in the eligible cohort, to show how much the adjustment moves it.

Negative control outcomes: conditions with no known causal link to either drug, named before seeing the data: viral sinusitis, acute viral pharyngitis, acute bronchitis, otitis media, streptococcal sore throat, sinusitis, chronic sinusitis, acute bacterial sinusitis, cystitis, and gingivitis. Each is matched by exact concept name (case-insensitive) with descendants, analyzed with the primary design among patients without that condition before index, and kept if it has at least 5 events in the matched cohort. With 5 or more kept, the systematic error distribution is fitted with EmpiricalCalibration and the primary CI is also reported after calibration.

## Checks and verdicts

| id | check | rule |
|---|---|---|
| P1 | Double programming: the eligible cohort, index dates, arms and outcome dates built in SQL match an independent dplyr build | identical |
| P2 | Equipoise: share of matched patients with a preference score between 0.3 and 0.7 | at least 50% |
| P3 | Covariate balance after matching, all covariates | max absolute standardized mean difference below 0.1 |
| P4 | Negative controls: 95% CIs that exclude 1 | at most 10% of the kept controls (and reported even if fewer than 5 are kept) |
| P5 | Direction of the primary estimate | hazard ratio below 1 |
| P6 | Sensitivity analyses 1 and 2 | same direction as the primary estimate |

A check that fails is reported as failed. Nothing is re-run to make it pass.

## Part B: code sets for a claims study of BPH procedures

A protocol-level code set, not run on data, for a claims-based study of men treated for benign prostatic hyperplasia (BPH): population (ICD-10-CM), procedure exposures including transurethral resection, laser procedures, prostatic urethral lift and water vapor thermal therapy (CPT and ICD-10-PCS), outcomes such as acute urinary retention and surgical retreatment (ICD-10-CM, CPT, ICD-10-PCS), and BPH drugs (RxNorm ingredients for alpha blockers and 5-alpha reductase inhibitors). Every ICD-10-CM and ICD-10-PCS code is checked against the official CMS code files for fiscal year 2026, and every RxNorm ingredient against the NLM RxNav API. CPT descriptions are written in my own words.

| id | check | rule |
|---|---|---|
| P7 | Every ICD-10-CM and ICD-10-PCS code in the Part B code sets exists in the CMS files, and every RxNorm ingredient resolves in RxNav | 100% |

## Amendments

**Amendment 1, after loading the data and before any outcome was compared between arms.** What the tables contain, and what follows from it:

- Every person has exactly one exposure record, 1,844 for celecoxib and 850 for diclofenac, and every record ends on its start date with days_supply 0. Under the era rule above, continuous exposure ends on the index day, so the on-treatment window is day 1 to day 30, the grace period. The rule is unchanged.
- Because each person has one record, the criteria on prior exposure and on starting both drugs exclude nobody. They stay in the code.
- The DEATH table is empty, so there is no censoring at death.
- Each person in PERSON has one observation period. OBSERVATION_PERIOD also has rows for person_ids that are not in PERSON, and those are ignored.
- The bundled vocabulary has no concepts for hypertension, diabetes (other than cystic fibrosis-related), chronic kidney disease, heart failure, direct oral anticoagulants, proton pump inhibitors or SSRIs. These covariates cannot be built and are listed as unavailable. Coronary heart disease is taken as "Coronary arteriosclerosis", the closest concept present. Systemic corticosteroids are prednisone, since hydrocortisone has no route recorded and is often topical. Anticoagulants are warfarin. Antiplatelets are aspirin and clopidogrel.
- Every patient has osteoarthritis, the indication, so it is constant and left out of the model.
- No concept named gingivitis exists, which leaves nine negative control outcomes.
- CONCEPT_RELATIONSHIP has eight rows. The only condition source code is ICD-10-CM K92.2, which maps to gastrointestinal hemorrhage, and it is listed in the outcome code set.

**Amendment 2, before Part B was checked.** The current ICD-10-CM and ICD-10-PCS release is for fiscal year 2027, so P7 uses those files. Since a claims study covers earlier years, each code is also looked up in the fiscal year 2026 files and the result is reported. The intended codes were written to `codesets/bph_spec.csv` before either file was opened. Prostatic urethral lift has no ICD-10-PCS code in the spec, because I could not settle its root operation without the coding guidance, and it is usually done as an outpatient procedure covered by CPT.
