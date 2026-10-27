# load the Eunomia CSVs into DuckDB
library(DBI)
raw <- "data/raw/GiBleed_5.3"
stopifnot(dir.exists(raw))
con <- dbConnect(duckdb::duckdb(), "data/cdm.duckdb")
for (f in list.files(raw, pattern = "\\.csv$", full.names = TRUE)) {
  tab <- tolower(sub("\\.csv$", "", basename(f)))
  dbExecute(con, sprintf("CREATE OR REPLACE TABLE %s AS SELECT * FROM read_csv('%s', header = true, all_varchar = false, sample_size = -1)", tab, f))
  # lower-case column names, as in the CDM spec
  cols <- dbListFields(con, tab)
  for (c in cols[cols != tolower(cols)]) dbExecute(con, sprintf('ALTER TABLE %s RENAME "%s" TO "%s"', tab, c, tolower(c)))
  # empty tables come in as text
  for (c in grep("_date$", tolower(cols), value = TRUE))
    dbExecute(con, sprintf('ALTER TABLE %s ALTER "%s" TYPE DATE USING TRY_CAST("%s" AS DATE)', tab, c, c))
}
n <- sapply(dbListTables(con), function(t) dbGetQuery(con, sprintf("SELECT count(*) AS n FROM %s", t))$n)
print(n[n > 0])
dbDisconnect(con, shutdown = TRUE)
