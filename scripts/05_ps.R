# propensity score, matching, balance
suppressPackageStartupMessages({ library(dplyr); library(glmnet) })
source("R/methods.R")
coh <- readRDS("data/derived/cohort_sql.rds")
cl <- readRDS("data/derived/cov_long.rds")
vis <- readRDS("data/derived/cov_visits.rds")
nm <- readRDS("data/derived/cov_names.rds")
n <- nrow(coh)

prev <- cl %>% count(covariate)
pre <- grepl("^(hist|rx)_", prev$covariate)
keep <- prev$covariate[(pre & prev$n >= 10) | (!pre & prev$n >= 0.01 * n)]
keep <- keep[prev$n[match(keep, prev$covariate)] < n]  # drop constant columns
X <- matrix(0, n, length(keep), dimnames = list(NULL, keep))
hit <- cl %>% filter(covariate %in% keep)
X[cbind(match(hit$person_id, coh$person_id), match(hit$covariate, keep))] <- 1
demo <- cbind(age = coh$age, male = as.numeric(coh$gender_concept_id == 8507),
              index_year = as.numeric(format(coh$index_date, "%Y")),
              n_visits = vis$n_visits[match(coh$person_id, vis$person_id)])
X <- cbind(demo, X)
pf <- ifelse(colnames(X) %in% c(colnames(demo), keep[grepl("^(hist|rx)_", keep)]), 0, 1)
treat <- as.integer(coh$arm == "celecoxib")

set.seed(2027)
fit <- cv.glmnet(X, treat, family = "binomial", nfolds = 10, penalty.factor = pf)
ps <- as.numeric(predict(fit, X, s = "lambda.min", type = "response"))
lp <- qlogis(ps)
pref <- pref_score(ps, treat)
pairs <- match_nn(lp, treat, caliper = 0.2 * sd(lp), seed = 2027)
m <- data.frame(row = c(pairs), pair = rep(seq_len(nrow(pairs)), 2))
matched <- coh[m$row, ]
matched$pair <- m$pair
matched$ps <- ps[m$row]
matched$pref <- pref[m$row]
saveRDS(matched, "data/derived/matched.rds")
saveRDS(data.frame(person_id = coh$person_id, treat, ps, pref), "data/derived/ps.rds")
saveRDS(X, "data/derived/X.rds")

lab <- function(v) {
  i <- match(v, nm$covariate)
  ifelse(is.na(i), gsub("_", " ", v), paste0(sub("_.*", "", v), ": ", nm$name[i]))
}
bal <- data.frame(covariate = colnames(X), label = lab(colnames(X)),
                  prevalence_celecoxib = colMeans(X[treat == 1, ]), prevalence_diclofenac = colMeans(X[treat == 0, ]),
                  smd_before = apply(X, 2, smd, treat = treat),
                  smd_after = apply(X[m$row, ], 2, smd, treat = treat[m$row]),
                  penalized = pf == 1,
                  coef = as.numeric(coef(fit, s = "lambda.min"))[-1])
write.csv(bal, "results/balance.csv", row.names = FALSE)

unavail <- read.csv("codesets/concept_sets.csv") %>% filter(set %in% c("history", "drug365"))
pre_status <- unavail %>% mutate(covariate = paste0(ifelse(set == "history", "hist_", "rx_"), label),
                                 patients = prev$n[match(covariate, prev$covariate)],
                                 in_model = covariate %in% colnames(X)) %>%
  select(set, label, concept_name, status, patients, in_model)
write.csv(pre_status, "results/prespecified_covariates.csv", row.names = FALSE)

eq <- mean(matched$pref >= 0.3 & matched$pref <= 0.7)
summ <- data.frame(eligible = n, celecoxib = sum(treat), diclofenac = sum(1 - treat), covariates = ncol(X),
                   nonzero_coefs = sum(coef(fit, s = "lambda.min")[-1] != 0), pairs = nrow(pairs),
                   caliper = 0.2 * sd(lp), equipoise_matched = eq, equipoise_all = mean(pref >= 0.3 & pref <= 0.7),
                   max_abs_smd_before = max(abs(bal$smd_before)), max_abs_smd_after = max(abs(bal$smd_after)))
write.csv(summ, "results/ps_summary.csv", row.names = FALSE)
print(t(summ))
print(head(bal[order(-abs(bal$smd_before)), c("label", "smd_before", "smd_after")], 10))
print(pre_status)
