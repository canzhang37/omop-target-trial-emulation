# pre-registered checks
qc <- read.csv("results/qc_double_programming.csv")
ps <- read.csv("results/ps_summary.csv")
nc <- read.csv("results/negative_controls.csv")
est <- read.csv("results/estimates.csv")
b <- read.csv("results/bph_check.csv")
kept <- if ("kept" %in% names(nc)) sum(nc$kept) else 0
excl <- if (kept > 0) sum(nc$kept & (nc$lo > 1 | nc$hi < 1)) else NA
f1 <- function(x) formatC(x, format = "f", digits = 2)
v <- data.frame(
  id = paste0("P", 1:7),
  check = c("SQL vs dplyr: cohort, arms, dates, events", "matched patients in equipoise (>= 50%)",
            "max |SMD| after matching (< 0.1)", "negative control CIs excluding 1 (<= 10%)",
            "primary HR below 1", "sensitivity 1 and 2 in the same direction",
            "ICD-10 codes in FY2027 files, RxNorm ingredients in RxNav (100%)"),
  value = c(paste(sum(qc$equal), "of", nrow(qc), "equal"), paste0(round(100 * ps$equipoise_matched), "%"),
            formatC(ps$max_abs_smd_after, format = "f", digits = 3),
            if (kept == 0) "0 of 9 controls had 5 events" else paste(excl, "of", kept),
            paste0(f1(est$hr[1]), " (", f1(est$lo[1]), "-", f1(est$hi[1]), ")"),
            paste0("ITT ", f1(est$hr[2]), ", IPTW ", f1(est$hr[3])),
            paste0(b$icd_in_fy2027, "/", b$icd_codes, " ICD, ", b$rxnorm_ingredients, "/", b$rxnorm, " RxNorm")),
  met = c(all(qc$equal), ps$equipoise_matched >= 0.5, ps$max_abs_smd_after < 0.1,
          if (kept == 0) NA else excl / kept <= 0.1, est$hr[1] < 1,
          sign(log(est$hr[2])) == sign(log(est$hr[1])) && sign(log(est$hr[3])) == sign(log(est$hr[1])),
          b$icd_in_fy2027 == b$icd_codes && b$rxnorm_ingredients == b$rxnorm))
v$met <- ifelse(is.na(v$met), "not evaluable", as.character(v$met))
write.csv(v, "results/verdicts.csv", row.names = FALSE)
print(v, right = FALSE)
