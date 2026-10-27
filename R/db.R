library(DBI)

cdm <- function(read_only = FALSE) dbConnect(duckdb::duckdb(), "data/cdm.duckdb", read_only = read_only)

# run a .sql file statement by statement
run_sql <- function(con, file) {
  txt <- paste(readLines(file, warn = FALSE), collapse = "\n")
  txt <- gsub("--[^\n]*", "", txt)
  stmts <- trimws(strsplit(txt, ";\\s*(\n|$)")[[1]])
  for (s in stmts[nzchar(stmts)]) dbExecute(con, s)
  invisible(length(stmts))
}
