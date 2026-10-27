# concept sets by name, resolved with descendants
library(DBI)
con <- dbConnect(duckdb::duckdb(), "data/cdm.duckdb")

spec <- read.csv("codesets/spec.csv", stringsAsFactors = FALSE)
look <- function(name, domain, cls) {
  sql <- "SELECT concept_id, concept_name, vocabulary_id, domain_id, concept_class_id FROM concept
          WHERE lower(concept_name) = lower(?) AND domain_id = ? AND standard_concept = 'S'"
  x <- dbGetQuery(con, sql, params = list(name, domain))
  if (cls != "") x <- x[x$concept_class_id == cls, ]
  x
}
rows <- lapply(seq_len(nrow(spec)), function(i) {
  s <- spec[i, ]
  x <- look(s$concept_name, s$domain, s$class)
  if (nrow(x) == 0) return(data.frame(s[c("set", "role", "label")], concept_id = NA, concept_name = s$concept_name,
                                      vocabulary_id = NA, domain_id = s$domain, status = "not in vocabulary"))
  data.frame(s[c("set", "role", "label")], x[c("concept_id", "concept_name", "vocabulary_id", "domain_id")], status = "found")
})
sets <- do.call(rbind, rows)
write.csv(sets, "codesets/concept_sets.csv", row.names = FALSE)

found <- sets[sets$status == "found", c("set", "role", "label", "concept_id")]
dbWriteTable(con, "codeset_root", found, overwrite = TRUE)
dbExecute(con, "CREATE OR REPLACE TABLE codeset AS
  SELECT r.set, r.role, r.label, a.descendant_concept_id AS concept_id
  FROM codeset_root r JOIN concept_ancestor a ON a.ancestor_concept_id = r.concept_id")
resolved <- dbGetQuery(con, "SELECT s.set, s.label, s.concept_id, c.concept_name, c.vocabulary_id
  FROM codeset s JOIN concept c USING (concept_id) ORDER BY 1, 2, 3")
write.csv(resolved, "codesets/resolved.csv", row.names = FALSE)

# source codes that map into a set
src <- dbGetQuery(con, "SELECT s.label, c.concept_code AS source_code, c.vocabulary_id AS source_vocabulary,
  c.concept_name AS source_name, s.concept_id AS maps_to
  FROM codeset s JOIN concept_relationship r ON r.concept_id_2 = s.concept_id AND r.relationship_id = 'Maps to'
  JOIN concept c ON c.concept_id = r.concept_id_1 ORDER BY 1, 2")
write.csv(src, "codesets/source_codes.csv", row.names = FALSE)

print(table(sets$set, sets$status))
print(src)
dbDisconnect(con, shutdown = TRUE)
