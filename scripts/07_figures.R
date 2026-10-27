suppressPackageStartupMessages({ library(dplyr); library(ggplot2) })
dir.create("figures", showWarnings = FALSE)
ps <- readRDS("data/derived/ps.rds")
m <- readRDS("data/derived/matched.rds")
arm <- function(t) factor(ifelse(t == 1, "celecoxib", "diclofenac"), c("celecoxib", "diclofenac"))
d <- bind_rows(data.frame(sample = "eligible", pref = ps$pref, arm = arm(ps$treat)),
               data.frame(sample = "matched", pref = m$pref, arm = arm(m$arm == "celecoxib")))
p <- ggplot(d, aes(pref, fill = arm)) +
  annotate("rect", xmin = 0.3, xmax = 0.7, ymin = -Inf, ymax = Inf, alpha = 0.08) +
  geom_density(alpha = 0.45, colour = NA) + facet_wrap(~sample) +
  scale_fill_manual(values = c(celecoxib = "#2b6cb0", diclofenac = "#c05621")) +
  labs(x = "preference score", y = "density", fill = NULL) + theme_minimal(11) + theme(legend.position = "top")
ggsave("figures/preference_score.png", p, width = 7, height = 3.4, dpi = 150)

bal <- read.csv("results/balance.csv")
p <- ggplot(bal, aes(abs(smd_before), abs(smd_after))) +
  geom_hline(yintercept = 0.1, linetype = 2, colour = "grey50") + geom_abline(slope = 1, colour = "grey80") +
  geom_point(size = 2, colour = "#2b6cb0") +
  geom_text(data = transform(subset(bal, abs(smd_before) > 0.2), h = ifelse(abs(smd_before) > 0.25 & abs(smd_before) < 0.4, 0, 1)),
            aes(label = label, hjust = h), vjust = -0.9, size = 3) +
  labs(x = "absolute SMD before matching", y = "absolute SMD after matching") +
  coord_cartesian(xlim = c(0, 0.55), ylim = c(0, 0.55)) + theme_minimal(11)
ggsave("figures/balance.png", p, width = 5, height = 4.4, dpi = 150)

est <- read.csv("results/estimates.csv")
cal <- read.csv("results/calibrated_itt_posthoc.csv")
nc <- read.csv("results/negative_controls_posthoc.csv") %>% filter(kept)
f <- bind_rows(
  est %>% transmute(group = "study outcome", label = analysis, hr, lo, hi),
  data.frame(group = "study outcome", label = "post hoc: ITT, calibrated on negative controls", hr = cal$hr, lo = cal$lo, hi = cal$hi),
  nc %>% transmute(group = "negative controls (post hoc, ITT)", label = gsub("_", " ", analysis), hr, lo, hi))
f$label <- factor(f$label, rev(f$label))
p <- ggplot(f, aes(hr, label)) + geom_vline(xintercept = 1, colour = "grey60") +
  geom_errorbar(aes(xmin = lo, xmax = hi), width = 0.2, orientation = "y") + geom_point(size = 2) +
  scale_x_log10() + facet_grid(group ~ ., scales = "free_y", space = "free_y") +
  labs(x = "hazard ratio, celecoxib vs diclofenac (log scale)", y = NULL) + theme_minimal(10)
ggsave("figures/estimates.png", p, width = 7.5, height = 5, dpi = 150)
