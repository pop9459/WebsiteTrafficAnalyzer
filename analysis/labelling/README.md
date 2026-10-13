# Validating the classifier (KAP-55, RQ1)

Question: how often does the rule-based `client_class` (human / bot / scanner / unknown) agree with an independent judgement?

## Method

1. `analysis/make_label_sheet.R` draws 200 anonymised requests, 50 per predicted class, and hides the predicted class (`label_sheet.csv`; the answer is in `label_key.csv`).
2. Four separate AI sessions (sonnet, opus, haiku, fable) label the sheet blind. Each gets only the sheet and a short rubric, never the classifier code or key. Files: `ai_labels_<model>.csv`.
3. `analysis/label_agreement.R [dir]` compares the classifier with each labeller and with the majority (a tie counts as unknown), and computes Cohen's kappa between labellers.
4. Two rounds, to avoid tuning on the measurement:
   - **Development sheet** (`analysis/labelling/`): used to find classifier mistakes. Its key holds the predictions of the first classifier version.
   - **Test sheet** (`analysis/labelling/test/`): a fresh sample (other seed, no request in common with the development sheet) measured after the classifier fix. This is the number to report.

Rubric, development round: scanner = path hunts for files the site does not have, or an attack tool; bot = automated, not hostile; human = real browser reading the site; unknown = cannot tell. It also told the labellers that a browser reaching the origin directly (not through Cloudflare) is suspicious.
Rubric, test round: the same, but `via_cloudflare` is informational only, and the scanner definition names "CMS or framework paths, random guessed paths".

## Results

| | Development sheet (old classifier) | Test sheet (new classifier) |
|---|---|---|
| Weighted accuracy against the majority | 93.0% | 98.1% |
| Macro-average precision (human, bot, scanner) | 79.9% | 99.2% |
| Precision human / bot / scanner | 70% / 72% / 98% | 100% / 98% / 100% |
| Rows with a decisive majority | 141 of 200 | 123 of 200 |
| All four labellers agree | 70.5% | 59.0% |

Per-class details and confusion matrices: `ai_label_summary.md` (development) and `test/ai_label_summary.md` (test).

## Read these numbers with care

- **The AI labels are not ground truth.** The figure is agreement with independent AI labellers.
- **Only decisive rows count.** Rows where the majority says `unknown` are left out: 77 of 200 in the test round. A single request often cannot prove that a visitor is human, so no labeller confirmed 28 of the 50 requests the classifier calls human. The accuracy holds for rows that are clear from the request alone.
- **The labellers are not fully independent.** Sonnet and fable agree on 97.5% of rows (kappa 0.96), opus is close, and haiku labels very liberally (97 of 200 as human in the test round; kappa about 0.5 against the others). Treat the majority as about two independent opinions.
- **The test rubric mirrors the fix.** Naming "random guessed paths" as scanner behaviour matches the new rule "a 404 for a path the site does not serve is a probe". That helps agreement. A rubric written without knowing the rule, or a human check, would be a harder test.
- **Single rows only.** The labellers do not see how often a client came back or what else it requested. Behaviour-based rules (bursts, 4xx share per user agent) cannot be judged from one row.
- **Stratified sample.** 50 per predicted class, so accuracy is re-weighted by the real class shares. Recall per class is not estimated.
