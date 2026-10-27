library(testthat)
source(file.path("..", "R", "methods.R"))
source(file.path("..", "R", "db.R"))

test_that("SMD matches a hand count", {
  x <- c(1, 1, 0, 0, 1, 0, 0, 0)
  t <- c(1, 1, 1, 1, 0, 0, 0, 0)
  s <- (0.5 - 0.25) / sqrt((var(x[1:4]) + var(x[5:8])) / 2)
  expect_equal(smd(x, t), s)
  expect_equal(smd(rep(1, 8), t), 0)
})

test_that("matching uses each control once and respects the caliper", {
  set.seed(3)
  lp <- c(rnorm(30), rnorm(60, 0.5))
  t <- rep(c(0, 1), c(30, 60))
  pr <- match_nn(lp, t, caliper = 0.1)
  expect_true(all(t[pr[, 1]] == 0) && all(t[pr[, 2]] == 1))
  expect_false(any(duplicated(pr[, 2])))
  expect_true(all(abs(lp[pr[, 1]] - lp[pr[, 2]]) <= 0.1))
})

test_that("E-value matches VanderWeele and Ding", {
  e <- evalue(3.9, 1.8, 8.7)
  expect_equal(unname(round(e["point"], 2)), 7.26)
  expect_equal(unname(round(e["ci"], 2)), 3)
  expect_equal(unname(evalue(0.8, 0.5, 1.2)["ci"]), 1)
})

test_that("cohort SQL builds eras, follow-up and events on toy records", {
  con <- dbConnect(duckdb::duckdb())
  on.exit(dbDisconnect(con, shutdown = TRUE))
  d <- function(x) as.Date(x)
  dbWriteTable(con, "codeset", data.frame(set = c("exposure", "exposure", "outcome"), role = "",
                                          label = c("celecoxib", "diclofenac", "gi"), concept_id = c(10, 20, 30)))
  dbWriteTable(con, "drug_exposure", data.frame(
    person_id = c(1, 1, 1, 2, 3), drug_concept_id = c(10, 10, 10, 20, 10),
    drug_exposure_start_date = d(c("2010-01-01", "2010-02-05", "2010-06-01", "2010-03-01", "2010-03-01")),
    drug_exposure_end_date = d(c("2010-01-10", NA, "2010-06-02", "2010-03-01", "2010-03-01")),
    days_supply = c(10, 5, 2, 0, 0)))
  dbWriteTable(con, "person", data.frame(person_id = c(1, 2, 3), gender_concept_id = 8507,
                                         year_of_birth = c(1950, 1960, 1995), month_of_birth = 1, day_of_birth = 1))
  dbWriteTable(con, "observation_period", data.frame(person_id = c(1, 2, 3),
    observation_period_start_date = d(c("2000-01-01", "2009-06-01", "2000-01-01")),
    observation_period_end_date = d(c("2020-01-01", "2020-01-01", "2020-01-01"))))
  dbWriteTable(con, "condition_occurrence", data.frame(person_id = 1, condition_concept_id = 30,
                                                       condition_start_date = d("2010-03-01")))
  dbWriteTable(con, "death", data.frame(person_id = numeric(0), death_date = as.Date(character(0))))
  run_sql(con, file.path("..", "sql", "cohort.sql"))
  era <- dbGetQuery(con, "SELECT * FROM exp_era WHERE person_id = 1 ORDER BY era")
  expect_equal(era$era_end, d(c("2010-02-10", "2010-06-02")))
  att <- dbGetQuery(con, "SELECT n FROM attrition ORDER BY step")$n
  expect_equal(att, c(3, 2, 1, 1, 1, 1))
  c1 <- dbGetQuery(con, "SELECT * FROM study_cohort WHERE person_id = 1")
  expect_equal(c1$ot_end, d("2010-03-12"))
  expect_true(c1$ot_event)
  expect_equal(c1$ot_days, 59)
})
