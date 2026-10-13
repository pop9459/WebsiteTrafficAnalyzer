# Compare the hand labels with the classifier (KAP-55, RQ1 success criterion).
#
# Usage (from the repo root, after filling analysis/labelling/label_sheet.csv):
#   Rscript analysis/label_accuracy.R
#
# The sheet is stratified (the same number of requests per predicted class), so
# the overall accuracy is weighted by the real class shares in the sample.
# Rows labelled `unknown` are reported but left out of the accuracy.

suppressPackageStartupMessages(library(dplyr))

sheet <- readr::read_csv("analysis/labelling/label_sheet.csv", show_col_types = FALSE)
key <- readr::read_csv("analysis/labelling/label_key.csv", show_col_types = FALSE)
sample <- readr::read_csv("data/sample/requests_sample.csv", show_col_types = FALSE)

labelled <- sheet |>
  inner_join(key, by = "id") |>
  mutate(label = tolower(trimws(label)))

stopifnot("label_sheet.csv has no labels yet" = any(!is.na(labelled$label)))
bad <- setdiff(na.omit(labelled$label), c("human", "bot", "scanner", "unknown"))
if (length(bad)) stop("Unknown labels: ", paste(bad, collapse = ", "))
if (anyNA(labelled$label)) warning(sum(is.na(labelled$label)), " rows are still unlabelled and are ignored.")

done <- filter(labelled, !is.na(label))
decided <- filter(done, label != "unknown")

cat("Labelled:", nrow(done), " of which 'cannot tell':", sum(done$label == "unknown"), "\n\n")
cat("Confusion matrix (rows = classifier, columns = your label):\n")
print(table(predicted = decided$predicted, label = decided$label))

per_class <- decided |>
  group_by(predicted) |>
  summarise(n = n(), correct = sum(predicted == label), precision = correct / n, .groups = "drop")

shares <- count(sample, predicted = client_class) |> mutate(share = n / sum(n)) |> select(predicted, share)
overall <- per_class |>
  inner_join(shares, by = "predicted") |>
  summarise(accuracy = sum(precision * share) / sum(share))

cat("\nPrecision per predicted class:\n")
print(as.data.frame(per_class), row.names = FALSE)
cat(sprintf("\nOverall accuracy, weighted by class share: %.1f%% (target: 90%%)\n", 100 * overall$accuracy))

wrong <- filter(decided, predicted != label)
if (nrow(wrong)) {
  cat("\nMisclassified requests (id, predicted, label, path):\n")
  print(as.data.frame(select(wrong, id, predicted, label, path, status)), row.names = FALSE)
}
