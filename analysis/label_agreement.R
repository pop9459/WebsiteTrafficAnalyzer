# Compare the classifier with independent AI labellers (KAP-55, RQ1).
#
# Usage (from the repo root, after make_label_sheet.R and the labellers'
# files <dir>/ai_labels_<name>.csv with columns id,label):
#   Rscript analysis/label_agreement.R [dir]
# dir is analysis/labelling (development sheet, default) or
# analysis/labelling/test (test sheet; the accuracy to report).
#
# Writes into dir
#   ai_label_summary.md   agreement, kappa, accuracy
#   review_sheet.csv      requests where the AI consensus contradicts the
#                         classifier, to adjudicate by hand (blind: no labels)
#   review_key.csv        classifier and AI labels per id
#
# The AI labels are a second, independent judgement, not ground truth: the
# report must say "agreement with independent AI labellers".

suppressPackageStartupMessages(library(dplyr))

dir <- if (length(commandArgs(trailingOnly = TRUE))) commandArgs(trailingOnly = TRUE)[[1]] else "analysis/labelling"
classes <- c("human", "bot", "scanner", "unknown")
files <- sort(list.files(dir, pattern = "^ai_labels_.*\\.csv$", full.names = TRUE))
stopifnot("no analysis/labelling/ai_labels_*.csv found" = length(files) > 0)

sheet <- readr::read_csv(file.path(dir, "label_sheet.csv"), show_col_types = FALSE)
key <- readr::read_csv(file.path(dir, "label_key.csv"), show_col_types = FALSE)

names(files) <- sub("^ai_labels_(.*)\\.csv$", "\\1", basename(files))
ai <- lapply(files, function(f) {
  x <- readr::read_csv(f, show_col_types = FALSE)
  stopifnot(setequal(x$id, key$id), all(x$label %in% classes))
  x$label[match(key$id, x$id)]
})
votes <- as.data.frame(ai, stringsAsFactors = FALSE)
k <- ncol(votes)

# Cohen's kappa between two label vectors ------------------------------------
kappa <- function(a, b) {
  tab <- table(factor(a, classes), factor(b, classes))
  n <- sum(tab)
  po <- sum(diag(tab)) / n
  pe <- sum(rowSums(tab) * colSums(tab)) / n^2
  if (pe == 1) return(NA_real_)
  (po - pe) / (1 - pe)
}

pairs <- utils::combn(names(votes), 2, simplify = FALSE)
pair_tab <- bind_rows(lapply(pairs, function(p) tibble(
  a = p[1], b = p[2],
  agreement = mean(votes[[p[1]]] == votes[[p[2]]]),
  kappa = kappa(votes[[p[1]]], votes[[p[2]]])
)))

# Majority label; a tie, or a majority for "unknown", counts as undecided.
consensus <- apply(votes, 1, function(v) {
  tab <- sort(table(v), decreasing = TRUE)
  if (length(tab) > 1 && tab[[1]] == tab[[2]]) "unknown" else names(tab)[1]
})
n_agree <- apply(votes, 1, function(v) max(table(v)))

d <- key |>
  mutate(consensus = consensus, votes_for_consensus = n_agree) |>
  bind_cols(votes)

# Accuracy of the classifier against each labeller and the consensus ---------
class_share <- if (file.exists("data/processed/requests.rds")) {
  count(readRDS("data/processed/requests.rds"), predicted = client_class)
} else {
  count(readr::read_csv("data/sample/requests_sample.csv", show_col_types = FALSE), predicted = client_class)
}
class_share <- mutate(class_share, share = n / sum(n)) |> select(predicted, share)

accuracy_against <- function(truth) {
  decided <- tibble(predicted = d$predicted, truth = truth) |> filter(truth != "unknown")
  per_class <- decided |>
    group_by(predicted) |>
    summarise(n = n(), correct = sum(predicted == truth), precision = correct / n, .groups = "drop") |>
    inner_join(class_share, by = "predicted")
  list(
    per_class = per_class,
    overall = sum(per_class$precision * per_class$share) / sum(per_class$share),
    decided = nrow(decided)
  )
}
acc <- c(lapply(votes, accuracy_against), list(consensus = accuracy_against(d$consensus)))
acc_tab <- tibble(
  labeller = names(acc),
  `rows decided` = vapply(acc, function(a) a$decided, integer(1)),
  `weighted accuracy` = vapply(acc, function(a) sprintf("%.1f%%", 100 * a$overall), character(1))
)

per_class_tab <- acc$consensus$per_class |>
  transmute(`classifier says` = predicted, rows = n, `AI consensus agrees` = correct,
            precision = sprintf("%.0f%%", 100 * precision), `share of requests` = sprintf("%.1f%%", 100 * share))

confusion <- table(classifier = d$predicted[d$consensus != "unknown"],
                   consensus = d$consensus[d$consensus != "unknown"])

# Rows for the human to look at ----------------------------------------------
# Only requests where the AI consensus is decisive and contradicts the
# classifier (rows the classifier calls "unknown" are no claim to contradict).
review_ids <- d$id[d$consensus != "unknown" & d$predicted != "unknown" & d$consensus != d$predicted]

sheet |>
  filter(id %in% review_ids) |>
  mutate(label = NA_character_) |>
  readr::write_csv(file.path(dir, "review_sheet.csv"))
d |> filter(id %in% review_ids) |> readr::write_csv(file.path(dir, "review_key.csv"))

# Summary ---------------------------------------------------------------------
md_table <- function(df) {
  df[] <- lapply(df, function(x) if (is.numeric(x)) format(round(x, 3), nsmall = 0) else as.character(x))
  c(paste0("| ", paste(names(df), collapse = " | "), " |"),
    paste0("|", paste(rep("---", ncol(df)), collapse = "|"), "|"),
    apply(df, 1, function(r) paste0("| ", paste(r, collapse = " | "), " |")))
}
label_counts <- bind_rows(lapply(names(votes), function(n) {
  tibble(labeller = n, !!!as.list(table(factor(votes[[n]], classes))))
}))

summary_lines <- c(
  "# Classifier vs independent AI labellers",
  "",
  paste0("Generated by `analysis/label_agreement.R` on ", format(Sys.Date()), ". ", k, " labellers, ", nrow(d), " requests (50 per predicted class: human, bot, scanner, unknown)."),
  "",
  "The AI labels are an independent second judgement, not ground truth.",
  "",
  "## Label counts per labeller", "", md_table(label_counts), "",
  "## Agreement between labellers", "", md_table(pair_tab |> mutate(agreement = sprintf("%.1f%%", 100 * agreement), kappa = sprintf("%.2f", kappa))), "",
  sprintf("All %d labellers agree on %d of %d rows (%.1f%%).", k, sum(n_agree == k), nrow(d), 100 * mean(n_agree == k)), "",
  "## Classifier accuracy (weighted by the real class shares; rows labelled unknown left out)", "",
  md_table(acc_tab), "",
  "Precision per predicted class, against the consensus:", "", md_table(per_class_tab), "",
  sprintf("Macro-average precision of human, bot and scanner (each class counts the same): %.1f%%.",
          100 * mean(acc$consensus$per_class$precision[acc$consensus$per_class$predicted != "unknown"])), "",
  "Confusion matrix (consensus, undecided rows left out):", "", "```", utils::capture.output(print(confusion)), "```", "",
  sprintf("Rows where the consensus contradicts the classifier (review_sheet.csv): %d.", length(review_ids))
)
writeLines(summary_lines, file.path(dir, "ai_label_summary.md"))
cat(summary_lines, sep = "\n")
