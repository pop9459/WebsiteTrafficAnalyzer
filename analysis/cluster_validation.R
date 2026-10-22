# Cluster direct-to-origin clients to validate the rule-based client_class (KAP-69).
#
# Usage (from the repo root, after data-raw/import_logs.R):
#   Rscript analysis/cluster_validation.R
#
# Writes analysis/cluster_validation.md and
# analysis/figures/14_client_clusters_pca.png. Aggregates only: cluster sizes,
# centroids, contingency tables and scores. No hashes or single-client rows
# are printed or stored.

suppressPackageStartupMessages({
  library(dplyr)
  library(ggplot2)
  devtools::load_all(quiet = TRUE)
})

requests <- readRDS("data/processed/requests.rds")
dir.create("analysis/figures", showWarnings = FALSE)

class_colours <- c(human = "#2a78d6", bot = "#eb6834", scanner = "#1baf7a", unknown = "#eda100", internal = "#e87ba4")
surface <- "#fcfcfb"
feature_cols <- c(
  "n_requests", "active_days", "share_4xx", "share_probe", "distinct_paths_ratio",
  "share_no_ua", "mean_requests_per_active_hour", "share_night"
)

clients <- client_features(requests)
n_requests_direct <- sum(!requests$via_cloudflare)
x <- scale(as.matrix(clients[feature_cols]))
x[is.na(x)] <- 0

# ---- k selection ---------------------------------------------------------
# Silhouette is computed on a random sample of at most 3,000 clients (exact
# distances inside the sample, clusters from the k-means fit on all clients).
set.seed(42)
sample_idx <- sample.int(nrow(x), min(3000, nrow(x)))
d_sample <- as.matrix(dist(x[sample_idx, , drop = FALSE]))

mean_silhouette <- function(cl, d) {
  cl <- cl[seq_len(nrow(d))]
  ks <- sort(unique(cl))
  if (length(ks) < 2) return(NA_real_)
  s <- vapply(seq_len(nrow(d)), function(i) {
    own <- cl == cl[i]
    if (sum(own) < 2) return(0)
    a <- sum(d[i, own]) / (sum(own) - 1)
    b <- min(vapply(setdiff(ks, cl[i]), function(k) mean(d[i, cl == k]), numeric(1)))
    (b - a) / max(a, b)
  }, numeric(1))
  mean(s)
}

fits <- list()
sel <- lapply(2:8, function(k) {
  set.seed(42)
  fit <- kmeans(x, centers = k, nstart = 25, iter.max = 100)
  fits[[as.character(k)]] <<- fit
  tibble(k = k, silhouette = mean_silhouette(fit$cluster[sample_idx], d_sample),
         smallest_cluster = min(fit$size), tot_withinss = fit$tot.withinss)
}) |> bind_rows()
best_k <- sel$k[which.max(sel$silhouette)]

# ---- agreement measures --------------------------------------------------
purity <- function(cluster, label) sum(apply(table(cluster, label), 1, max)) / length(label)
ari <- function(a, b) {
  tab <- table(a, b)
  c2 <- function(v) v * (v - 1) / 2
  sum_ij <- sum(c2(tab))
  sum_a <- sum(c2(rowSums(tab)))
  sum_b <- sum(c2(colSums(tab)))
  expected <- sum_a * sum_b / c2(sum(tab))
  (sum_ij - expected) / ((sum_a + sum_b) / 2 - expected)
}

ks_report <- unique(c(best_k, 3, 4))
agree <- lapply(ks_report, function(k) {
  cl <- fits[[as.character(k)]]$cluster
  tibble(k = k, purity = purity(cl, clients$majority_class), ari = ari(cl, clients$majority_class))
}) |> bind_rows()
baseline_purity <- max(table(clients$majority_class)) / nrow(clients)

# ---- markdown helpers ----------------------------------------------------
md_table <- function(df) {
  df[] <- lapply(df, function(v) if (is.numeric(v)) format(round(v, 3), nsmall = 0, trim = TRUE) else as.character(v))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}

centroids <- function(k) {
  cl <- fits[[as.character(k)]]$cluster
  raw <- clients
  raw$n_requests <- expm1(raw$n_requests)
  raw$mean_requests_per_active_hour <- expm1(raw$mean_requests_per_active_hour)
  raw$cluster <- cl
  raw |>
    group_by(cluster) |>
    summarise(clients = n(), across(all_of(feature_cols), mean), .groups = "drop") |>
    rename(requests_per_client = n_requests, requests_per_active_hour = mean_requests_per_active_hour)
}

contingency <- function(k) {
  cl <- fits[[as.character(k)]]$cluster
  tab <- table(cluster = cl, majority_class = clients$majority_class)
  counts <- as.data.frame.matrix(tab)
  pct <- as.data.frame.matrix(round(100 * prop.table(tab, 1), 1))
  names(pct) <- paste0(names(pct), " %")
  bind_cols(tibble(cluster = rownames(counts), clients = rowSums(counts)), counts, pct)
}

# Feature means and request-volume buckets per rule-based class.
class_means <- clients |>
  mutate(n_requests = expm1(n_requests), mean_requests_per_active_hour = expm1(mean_requests_per_active_hour)) |>
  group_by(majority_class) |>
  summarise(clients = n(), across(all_of(feature_cols), mean), .groups = "drop") |>
  rename(requests_per_client = n_requests, requests_per_active_hour = mean_requests_per_active_hour)
volume_bucket <- cut(expm1(clients$n_requests), c(0, 1, 4, 20, Inf), labels = c("1", "2-4", "5-20", ">20"))
volume_tab <- as.data.frame.matrix(table(clients$majority_class, volume_bucket))
volume <- bind_cols(tibble(majority_class = rownames(volume_tab)), volume_tab)

# ---- PCA figure (chosen k) -----------------------------------------------
pca <- prcomp(x)
var_expl <- summary(pca)$importance[2, 1:2]
plot_k <- best_k
pc <- tibble(PC1 = pca$x[, 1], PC2 = pca$x[, 2],
             cluster = factor(fits[[as.character(plot_k)]]$cluster),
             majority_class = clients$majority_class)
set.seed(42)
pc <- pc[sample.int(nrow(pc), min(6000, nrow(pc))), ]
p <- ggplot(pc, aes(PC1, PC2, colour = cluster, shape = majority_class)) +
  geom_point(alpha = 0.55, size = 1.6) +
  scale_colour_manual(values = c("#0072B2", "#E69F00", "#009E73", "#D55E00", "#CC79A7", "#56B4E9", "#F0E442", "#666666")[seq_len(plot_k)]) +
  labs(
    title = sprintf("Direct-to-origin clients: k-means clusters (k = %d) in PCA space", plot_k),
    subtitle = "Colour = cluster, shape = majority rule-based class (random sample of up to 6,000 clients)",
    x = sprintf("PC1 (%.0f%% of variance)", 100 * var_expl[1]),
    y = sprintf("PC2 (%.0f%% of variance)", 100 * var_expl[2]),
    colour = "Cluster", shape = "Majority class"
  ) +
  theme_minimal(base_size = 11) +
  theme(plot.background = element_rect(fill = surface, colour = NA),
        panel.background = element_rect(fill = surface, colour = NA),
        legend.position = "bottom")
ggsave("analysis/figures/14_client_clusters_pca.png", p, width = 9, height = 6, dpi = 150, bg = surface)

# ---- discussion (written after reading the tables above; see git history) --
discussion <- if (file.exists("analysis/cluster_validation_discussion.md")) {
  readLines("analysis/cluster_validation_discussion.md")
} else {
  "_Discussion file not written yet._"
}

# ---- write markdown ------------------------------------------------------
class_counts <- as.data.frame(table(majority_class = clients$majority_class))
out <- c(
  "# Cluster validation of the rule-based client classes (KAP-69)", "",
  "Generated by `analysis/cluster_validation.R`. Aggregates only.", "",
  "## Data", "",
  sprintf("- Direct-to-origin requests (`via_cloudflare == FALSE`): %s of %s (%.1f%%).",
          format(n_requests_direct, big.mark = ","), format(nrow(requests), big.mark = ","),
          100 * n_requests_direct / nrow(requests)),
  sprintf("- Clients (distinct hashed addresses) in those requests: %s.", format(nrow(clients), big.mark = ",")),
  "- Features (scaled to mean 0, sd 1 before clustering): log requests, active days, share 4xx, share probe requests, distinct-path ratio, share without user agent, log mean requests per active hour, share at night (00-06 UTC).",
  "- `majority_class` (most common `client_class` of a client's requests) is **not** used for clustering; it is only the label we compare with.", "",
  "Clients by majority class:", "", md_table(class_counts), "",
  "Feature means by majority class (unscaled):", "", md_table(class_means), "",
  "Clients by number of requests (rows: majority class):", "", md_table(volume), "",
  "## Choosing k", "",
  sprintf("k-means (`stats::kmeans`, `nstart = 25`, `set.seed(42)`) for k = 2..8. The mean silhouette width is computed on a random sample of %s clients (exact distances inside the sample, cluster labels from the fit on all clients), because the `cluster` package is not installed and the sample keeps the O(n^2) distance computation small.",
          format(length(sample_idx), big.mark = ",")), "",
  md_table(sel), "",
  sprintf("Best k by silhouette: **%d** (%.3f). k = 3 and k = 4 are also reported for interpretability.", best_k, max(sel$silhouette)), "",
  "## Agreement with the rule-based class", "",
  sprintf("Purity = share of clients whose cluster's most common majority class equals their own. Always predicting the largest class gives a purity of %.3f. The adjusted Rand index (ARI) is 0 for random agreement and 1 for identical partitions.", baseline_purity), "",
  md_table(agree), ""
)
for (k in ks_report) {
  out <- c(out,
    sprintf("## k = %d%s", k, if (k == best_k) " (best silhouette)" else ""), "",
    "Cluster centroids (unscaled feature means):", "", md_table(centroids(k)), "",
    "Cluster x majority class (counts, then row %):", "", md_table(contingency(k)), "")
}
out <- c(out,
  "## PCA", "",
  sprintf("![Clusters in PCA space](figures/14_client_clusters_pca.png)"), "",
  sprintf("The first two components explain %.0f%% and %.0f%% of the variance.", 100 * var_expl[1], 100 * var_expl[2]), "",
  "## Discussion", "", discussion, "")
writeLines(out, "analysis/cluster_validation.md")
cat(out[seq_len(min(length(out), 400))], sep = "\n")
