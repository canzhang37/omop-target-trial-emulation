# balance, matching, E-value

smd <- function(x, treat, w = NULL) {
  if (is.null(w)) w <- rep(1, length(x))
  m1 <- weighted.mean(x[treat == 1], w[treat == 1])
  m0 <- weighted.mean(x[treat == 0], w[treat == 0])
  # pooled SD from unweighted groups, as in cobalt
  v1 <- var(x[treat == 1]); v0 <- var(x[treat == 0])
  s <- sqrt((v1 + v0) / 2)
  if (s == 0) return(0)
  (m1 - m0) / s
}

pref_score <- function(ps, treat) {
  p <- mean(treat)
  plogis(qlogis(ps) - qlogis(p))
}

# 1:1 greedy nearest neighbor, no replacement;
# smaller arm taken in random order
match_nn <- function(lp, treat, caliper, seed = 1) {
  small <- as.integer(names(which.min(table(treat))))
  focal <- which(treat == small)
  pool <- which(treat != small)
  set.seed(seed)
  focal <- focal[sample.int(length(focal))]
  used <- rep(FALSE, length(lp))
  pairs <- matrix(NA_integer_, 0, 2)
  for (i in focal) {
    cand <- pool[!used[pool]]
    if (!length(cand)) break
    d <- abs(lp[cand] - lp[i])
    j <- which.min(d)
    if (d[j] <= caliper) {
      used[cand[j]] <- TRUE
      pairs <- rbind(pairs, c(i, cand[j]))
    }
  }
  pairs
}

evalue <- function(est, lo, hi) {
  ev <- function(rr) {
    if (rr < 1) rr <- 1 / rr
    rr + sqrt(rr * (rr - 1))
  }
  near <- if (lo <= 1 && hi >= 1) 1 else if (est < 1) hi else lo
  c(point = ev(est), ci = if (near == 1) 1 else ev(near))
}
