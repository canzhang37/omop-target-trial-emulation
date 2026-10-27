# Part B: BPH codes vs CMS files and RxNav
suppressPackageStartupMessages({ library(dplyr); library(jsonlite) })
cms <- "data/raw/cms"
read_codes <- function(zip, pattern) {
  f <- grep(pattern, unzip(file.path(cms, zip), list = TRUE)$Name, value = TRUE)
  x <- readLines(unz(file.path(cms, zip), f), warn = FALSE, encoding = "latin1")
  data.frame(code = trimws(substr(x, 1, 7)), description = trimws(substr(x, 8, nchar(x))))
}
cm <- list(fy2027 = read_codes("2027-code-descriptions-tabular-order.zip", "icd10cm_codes_2027\\.txt$"),
           fy2026 = read_codes("2026-code-descriptions-tabular-order.zip", "icd10cm_codes_2026\\.txt$"))
pcs <- list(fy2027 = read_codes("2027-icd-10-pcs-codes-file.zip", "icd10pcs_codes_2027\\.txt$"),
            fy2026 = read_codes("2026-icd-10-pcs-codes-file.zip", "icd10pcs_codes_2026\\.txt$"))

rxnav <- function(name) {
  u <- sprintf("https://rxnav.nlm.nih.gov/REST/rxcui.json?name=%s&search=0", URLencode(name))
  id <- fromJSON(u)$idGroup$rxnormId
  if (is.null(id)) return(c(rxcui = NA, rx_name = NA, tty = NA))
  p <- fromJSON(sprintf("https://rxnav.nlm.nih.gov/REST/rxcui/%s/properties.json", id[1]))$properties
  c(rxcui = p$rxcui, rx_name = p$name, tty = p$tty)
}

spec <- read.csv("codesets/bph_spec.csv", stringsAsFactors = FALSE)
out <- bind_rows(lapply(seq_len(nrow(spec)), function(i) {
  s <- spec[i, ]
  k <- gsub("\\.", "", s$code)
  if (s$system %in% c("ICD10CM", "ICD10PCS")) {
    tab <- if (s$system == "ICD10CM") cm else pcs
    j <- match(k, tab$fy2027$code)
    data.frame(s, official_description = if (is.na(j)) NA else tab$fy2027$description[j],
               in_fy2027 = !is.na(j), in_fy2026 = k %in% tab$fy2026$code, rxcui = NA, checked = TRUE)
  } else if (s$system == "RxNorm") {
    r <- rxnav(s$code)
    data.frame(s, official_description = r[["rx_name"]], in_fy2027 = NA, in_fy2026 = NA,
               rxcui = r[["rxcui"]], checked = TRUE, tty = r[["tty"]])
  } else {
    data.frame(s, official_description = NA, in_fy2027 = NA, in_fy2026 = NA, rxcui = NA, checked = FALSE)
  }
}))
write.csv(out, "codesets/bph_codesets.csv", row.names = FALSE, na = "")
icd <- out %>% filter(system %in% c("ICD10CM", "ICD10PCS"))
rx <- out %>% filter(system == "RxNorm")
p7 <- data.frame(icd_codes = nrow(icd), icd_in_fy2027 = sum(icd$in_fy2027), icd_in_fy2026 = sum(icd$in_fy2026),
                 rxnorm = nrow(rx), rxnorm_ingredients = sum(rx$tty %in% "IN"),
                 cpt_not_checked = sum(out$system == "CPT"))
write.csv(p7, "results/bph_check.csv", row.names = FALSE)
print(out %>% select(system, code, official_description, in_fy2027, in_fy2026, rxcui), right = FALSE)
print(p7)
