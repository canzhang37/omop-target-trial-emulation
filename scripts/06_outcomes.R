# primary, sensitivity, negative controls
suppressPackageStartupMessages({ library(dplyr); library(survival); library(EmpiricalCalibration) })
source("R/methods.R")
m <- readRDS("data/derived/matched.rds")
coh <- readRDS("data/derived/cohort_sql.rds")
ps <- readRDS("data/derived/ps.rds")
nc <- readRDS("data/derived/nc_outcome.rds")
m$celecoxib <- as.integer(m$arm == "celecoxib")
coh$celecoxib <- as.integer(coh$arm == "celecoxib")

cox_row <- function(fit, d, time, event, analysis) {
  s <- summary(fit)$coefficients
  b <- s["celecoxib", "coef"]
  se <- s["celecoxib", if ("robust se" %in% colnames(s)) "robust se" else "se(coef)"]
  by_arm <- function(a) c(n = sum(d$celecoxib == a), events = sum(d[[event]][d$celecoxib == a]),
                          py = sum(d[[time]][d$celecoxib == a]) / 365.25)
  e1 <- by_arm(1); e0 <- by_arm(0)
  data.frame(analysis, log_hr = b, se = se, hr = exp(b), lo = exp(b - 1.96 * se), hi = exp(b + 1.96 * se),
             n_celecoxib = e1[["n"]], events_celecoxib = e1[["events"]], py_celecoxib = e1[["py"]],
             n_diclofenac = e0[["n"]], events_diclofenac = e0[["events"]], py_diclofenac = e0[["py"]])
}

res <- list()
f <- coxph(Surv(ot_days, ot_event) ~ celecoxib + cluster(pair), data = m)
res$primary <- cox_row(f, m, "ot_days", "ot_event", "primary: matched, on-treatment (days 1-30)")
f <- coxph(Surv(itt_days, itt_event) ~ celecoxib + cluster(pair), data = m)
res$itt <- cox_row(f, m, "itt_days", "itt_event", "sensitivity 1: matched, intention to treat (days 1-365)")

coh$ps <- ps$ps[match(coh$person_id, ps$person_id)]
p <- mean(coh$celecoxib)
w <- ifelse(coh$celecoxib == 1, p / coh$ps, (1 - p) / (1 - coh$ps))
q <- quantile(w, c(0.01, 0.99))
coh$w <- pmin(pmax(w, q[1]), q[2])
f <- coxph(Surv(ot_days, ot_event) ~ celecoxib, data = coh, weights = w, robust = TRUE)
res$iptw <- cox_row(f, coh, "ot_days", "ot_event", "sensitivity 2: IPTW, on-treatment")
f <- coxph(Surv(ot_days, ot_event) ~ celecoxib, data = coh)
res$crude <- cox_row(f, coh, "ot_days", "ot_event", "sensitivity 3: unadjusted, on-treatment")
est <- bind_rows(res)

# negative controls
labs <- read.csv("codesets/concept_sets.csv") %>% filter(set == "negative_control", status == "found") %>% pull(label)
ncr <- bind_rows(lapply(labs, function(l) {
  x <- nc %>% filter(label == l)
  d <- m %>% left_join(x %>% select(person_id, prior, first_after), by = "person_id") %>%
    filter(is.na(prior) | prior == 0) %>%
    mutate(ev = !is.na(first_after) & first_after <= ot_end,
           days = as.numeric(ifelse(ev, first_after - index_date, ot_end - index_date)))
  events <- sum(d$ev)
  if (events < 5) return(data.frame(analysis = l, events = events, kept = FALSE))
  f <- coxph(Surv(days, ev) ~ celecoxib + cluster(pair), data = d)
  r <- cox_row(f, d %>% mutate(days = days), "days", "ev", l)
  cbind(r, events = events, kept = TRUE)
}))

kept <- ncr %>% filter(kept)
cal <- NULL
if (nrow(kept) >= 5) {
  null <- fitNull(kept$log_hr, kept$se)
  model <- convertNullToErrorModel(null)
  ci <- calibrateConfidenceInterval(est$log_hr[1], est$se[1], model)
  cal <- data.frame(null_mean = null[["mean"]], null_sd = null[["sd"]],
                    hr = exp(ci$logRr), lo = exp(ci$logLb95Rr), hi = exp(ci$logUb95Rr))
  write.csv(cal, "results/calibrated_primary.csv", row.names = FALSE)
}

# post hoc: 365-day washout, ITT window
ncp <- bind_rows(lapply(labs, function(l) {
  x <- nc %>% filter(label == l)
  d <- m %>% left_join(x %>% select(person_id, prior365, first_after), by = "person_id") %>%
    filter(is.na(prior365) | prior365 == 0) %>%
    mutate(ev = !is.na(first_after) & first_after <= itt_end,
           days = as.numeric(ifelse(ev, first_after - index_date, itt_end - index_date)))
  events <- sum(d$ev)
  if (events < 5) return(data.frame(analysis = l, events = events, kept = FALSE))
  f <- coxph(Surv(days, ev) ~ celecoxib + cluster(pair), data = d)
  cbind(cox_row(f, d, "days", "ev", l), events = events, kept = TRUE)
}))
write.csv(ncp, "results/negative_controls_posthoc.csv", row.names = FALSE)
kp <- ncp %>% filter(kept)
if (nrow(kp) >= 5) {
  null <- fitNull(kp$log_hr, kp$se)
  ci <- calibrateConfidenceInterval(est$log_hr[2], est$se[2], convertNullToErrorModel(null))
  calp <- data.frame(estimate = est$analysis[2], null_mean = null[["mean"]], null_sd = null[["sd"]],
                     hr = exp(ci$logRr), lo = exp(ci$logLb95Rr), hi = exp(ci$logUb95Rr))
  write.csv(calp, "results/calibrated_itt_posthoc.csv", row.names = FALSE)
  print(calp)
}
print(ncp[, intersect(c("analysis", "events", "kept", "hr", "lo", "hi"), names(ncp))])

# weighted balance for the IPTW analysis
X <- readRDS("data/derived/X.rds")
wsmd <- apply(X, 2, smd, treat = coh$celecoxib, w = coh$w)
write.csv(data.frame(covariate = colnames(X), smd_iptw = wsmd), "results/balance_iptw.csv", row.names = FALSE)

ev <- evalue(est$hr[1], est$lo[1], est$hi[1])
est$evalue_point <- c(ev[["point"]], rep(NA, nrow(est) - 1))
est$evalue_ci <- c(ev[["ci"]], rep(NA, nrow(est) - 1))
write.csv(est, "results/estimates.csv", row.names = FALSE)
write.csv(ncr, "results/negative_controls.csv", row.names = FALSE)
print(est[, c("analysis", "hr", "lo", "hi", "events_celecoxib", "events_diclofenac")])
print(ncr[, intersect(c("analysis", "events", "kept", "hr", "lo", "hi"), names(ncr))])
print(cal)
