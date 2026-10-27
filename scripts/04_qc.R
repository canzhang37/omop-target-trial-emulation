# independent dplyr build from raw CSVs
suppressPackageStartupMessages({ library(dplyr); library(readr) })
raw <- "data/raw/GiBleed_5.3"
rd <- function(t) {
  x <- read_csv(file.path(raw, paste0(t, ".csv")), show_col_types = FALSE, guess_max = 1e6, progress = FALSE)
  names(x) <- tolower(names(x))
  x
}
concept <- rd("CONCEPT"); anc <- rd("CONCEPT_ANCESTOR"); de <- rd("DRUG_EXPOSURE")
co <- rd("CONDITION_OCCURRENCE"); person <- rd("PERSON"); op <- rd("OBSERVATION_PERIOD"); death <- rd("DEATH")
# empty DEATH table: fix column types
death <- death %>% transmute(person_id = as.numeric(person_id), death_date = as.Date(as.character(death_date)))

ing <- concept %>%
  filter(vocabulary_id == "RxNorm", concept_class_id == "Ingredient", tolower(concept_name) %in% c("celecoxib", "diclofenac")) %>%
  transmute(ancestor_concept_id = concept_id, arm = tolower(concept_name))
drug_arm <- anc %>% inner_join(ing, by = "ancestor_concept_id") %>% select(drug_concept_id = descendant_concept_id, arm)
gib_root <- concept %>% filter(concept_name == "Gastrointestinal hemorrhage", standard_concept == "S") %>% pull(concept_id)
gib <- anc %>% filter(ancestor_concept_id == gib_root) %>% pull(descendant_concept_id)

rec <- de %>% inner_join(drug_arm, by = "drug_concept_id") %>%
  transmute(person_id, arm, start = as.Date(drug_exposure_start_date),
            end = coalesce(as.Date(drug_exposure_end_date), start + coalesce(days_supply, 29)))
era <- rec %>% arrange(person_id, arm, start, end) %>% group_by(person_id, arm) %>%
  mutate(prev_end = lag(as.Date(cummax(as.numeric(end)))),
         era = cumsum(is.na(prev_end) | start > prev_end + 30)) %>%
  group_by(person_id, arm, era) %>% summarise(era_start = min(start), era_end = max(end), .groups = "drop")
first <- era %>% group_by(person_id, arm) %>% summarise(first_start = min(era_start), .groups = "drop")
cand <- first %>% group_by(person_id) %>% filter(first_start == min(first_start)) %>%
  summarise(index_date = first(first_start), arm = min(arm), n_arms = n(), .groups = "drop")

age_at <- function(birth, d) {
  b <- as.POSIXlt(birth); x <- as.POSIXlt(d)
  (x$year - b$year) - ((x$mon < b$mon) | (x$mon == b$mon & x$mday < b$mday))
}
gib_dates <- co %>% filter(condition_concept_id %in% gib) %>% select(person_id, d = condition_start_date)

elig <- cand %>%
  inner_join(person %>% transmute(person_id, birth = as.Date(sprintf("%d-%02d-%02d", year_of_birth,
             coalesce(month_of_birth, 1), coalesce(day_of_birth, 1)))), by = "person_id") %>%
  mutate(age = age_at(birth, index_date)) %>%
  left_join(op %>% transmute(person_id, os = as.Date(observation_period_start_date), oe = as.Date(observation_period_end_date)),
            by = "person_id") %>%
  filter(is.na(os) | (index_date >= os & index_date <= oe)) %>%
  filter(age >= 18, !is.na(os), os <= index_date - 365, n_arms == 1) %>%
  anti_join(rec %>% select(person_id, start), by = join_by(person_id, index_date > start)) %>%
  anti_join(gib_dates, by = join_by(person_id, index_date >= d))

far <- as.Date("9999-12-31")
qc <- elig %>%
  left_join(era %>% select(person_id, arm, era_start, era_end), by = join_by(person_id, arm, index_date == era_start)) %>%
  left_join(rec %>% rename(sw_arm = arm, sw = start) %>% select(person_id, sw_arm, sw), by = "person_id", relationship = "many-to-many") %>%
  group_by(person_id, arm, index_date, oe, era_end) %>%
  summarise(switch_date = suppressWarnings(min(sw[sw_arm != arm & sw > index_date])), .groups = "drop") %>%
  mutate(switch_date = if_else(is.finite(switch_date), switch_date, as.Date(NA))) %>%
  left_join(death %>% group_by(person_id) %>% summarise(dd = suppressWarnings(min(death_date))), by = "person_id") %>%
  left_join(gib_dates %>% rename(od = d), by = "person_id", relationship = "many-to-many") %>%
  group_by(person_id, arm, index_date, oe, era_end, switch_date, dd) %>%
  summarise(outcome_date = suppressWarnings(min(od[od > index_date])), .groups = "drop") %>%
  mutate(outcome_date = if_else(is.finite(outcome_date), outcome_date, as.Date(NA)),
         ot_end = pmin(era_end + 30, index_date + 365, oe, coalesce(switch_date - 1, far), coalesce(dd, far)),
         itt_end = pmin(index_date + 365, oe, coalesce(dd, far)),
         ot_event = !is.na(outcome_date) & outcome_date <= ot_end,
         itt_event = !is.na(outcome_date) & outcome_date <= itt_end) %>%
  arrange(person_id)

sq <- readRDS("data/derived/cohort_sql.rds") %>% arrange(person_id)
cols <- c("person_id", "arm", "index_date", "outcome_date", "ot_end", "itt_end", "ot_event", "itt_event")
same_ids <- identical(sq$person_id, qc$person_id)
res <- data.frame(check = c("patients", "same person_ids", cols[-1]),
                  sql = c(nrow(sq), NA, rep(NA, length(cols) - 1)),
                  dplyr = c(nrow(qc), NA, rep(NA, length(cols) - 1)),
                  equal = c(nrow(sq) == nrow(qc), same_ids,
                            sapply(cols[-1], function(v) same_ids && isTRUE(all.equal(as.character(sq[[v]]), as.character(qc[[v]]))))))
write.csv(res, "results/qc_double_programming.csv", row.names = FALSE)
print(res)
