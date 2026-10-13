# CP2 talk script, 5 minutes (DRAFT for review, KAP-7)

Numbers are from the 9 Jul – 3 Oct 2026 log (298,296 requests, 86 days) unless stated. Figures are in `analysis/figures/`; regenerate with `Rscript analysis/first_look.R` and `Rscript analysis/fix_effect.R`.

## 1. The question (~30 s)

**Say:** "kapsiar.sk gets far more traffic than a small portfolio site should. I'm analysing its web-server logs to find out who sends it: real people, bots or scanners, and what to do about it."

*Means:* the question from the CP1 pitch. Logs are Apache access logs, one line per request.

## 2. What I built (~45 s)

**Say:** "An R package that reads the raw log, parses every line, hashes the IP addresses so no real address is stored, and classifies each request. It has 80 automated test checks and passes R CMD check on Linux, macOS and Windows in CI. Logs now persist on the server, and I fetch them with a read-only key that can do nothing else."

*Means:*
- **Anonymise:** salted one-way hash, same IP gives the same hash, so I can group per client without storing the address. Salt stays outside the repo.
- **Persist and fetch:** the logs used to vanish when the Docker container was recreated. They are now written to disk with extra fields (bytes in/out, response time, the visitor's real address behind Cloudflare).
- **CI:** automated check on every push.

## 3. Findings (~2 min)

**a) Almost all traffic is scanners.** **Say:** "About 85% of requests are scanners, 6.5% bots, and only 1.5% look human. 81% of all requests end in an error." **Show:** `01_requests_per_week_by_class.png`.
*Means:* a scanner is an automated program that tries thousands of sites for known weaknesses. A 4xx status mostly means "not found". The human share is tiny: about 35 page visits per day.

**b) What they look for.** **Say:** "Most probes are PHP backdoors and `.env` files, about 48,000 each, then `.git` folders." **Show:** `03_probe_families.png`.
*Means:* a `.env` file usually holds passwords, a `.git` folder holds the source code.

**c) The big one: my site exposed its `.git` folder, and I fixed it.** **Say:** "Scanners downloading my exposed `.git` folder caused 9 of the 9.5 GB my server sent out. That is 95% of my outgoing traffic. I fixed it on 7 October. Since then outgoing data dropped from 110 to 1.8 megabytes per day, a 98% drop, and no probe for an exposed file is answered any more. Scanners still come, even more per day, but get nothing." **Show:** `06_fix_effect.png`.
*Means:* the website repo was mounted as the web root, so every file was public. No passwords were committed. After the fix the server answers those requests with a refusal. The "after" window is only 6 days, so I will re-check later.

**d) I caught my own classifier being wrong.** **Say:** "My first version called 6.6% of requests human. Looking closer, many of those came in bursts of hundreds of requests per hour from one browser string, and 56% of them got errors. People don't do that. I added rules for it and the human share is now 1.5%." **Show:** `05_hour_of_day_by_class.png`.
*Means:* the earlier chart had spikes at exactly 06, 13 and 18 UTC, which pointed to automated programs. They are gone.

**e) How I checked the classifier.** **Say:** "I had four independent AI sessions label 200 fresh requests without seeing my results. On the rows where they reached a clear majority, which is 62% of the sample, my classifier agreed 98% of the time. It is agreement with AI judges, not proof, and a single log line often can't show whether a visitor is a person. A human spot-check is still on my list." **Show:** nothing, or the table in `analysis/labelling/README.md`.
*Means:* I tested the classifier on a sample it was not tuned on. Limits: labellers partly agree with each other, undecided rows are left out.

**f) Cloudflare complicates the data.** **Say:** "The site is behind Cloudflare, so for 56% of the requests I only see Cloudflare's address, not the visitor's. The other 44% go directly to my server, and almost all of those are scanners."
*Means:* normal visitors always arrive through Cloudflare. Scanners that sweep IP ranges hit the server directly.

## 4. What I did with the CP1 feedback (~30 s)

**Say:** "You suggested comparing my data with public data. That is research question 3. I shortlisted three sources: Cloudflare Radar for the global share of bot traffic, a public list of known crawler user agents, and the NASA web-server logs from 1995 as a baseline of a normal site. Comparison comes next."
*Means:* `docs/public_datasets.md` has licences and the comparison plan. I dropped threat-IP lists because they need real IP addresses.

## 5. Next steps and where I'm stuck (~1 min)

**Say:**
- "Process the older logs, June 2025 to May 2026, to look for the September 2025 traffic spike from the pitch."
- "Stuck: the pitch was about incoming traffic, about 40 GB a month. My logs only record outgoing bytes up to 7 October, and the web traffic explains far less than that. The new log format records incoming bytes, so I can check whether it was really web traffic."
- "Decide how to show results in the existing website, then build the dashboard."
- "Add country and network of each visitor, and cluster clients by behaviour as a second check of the classifier."

**Ask the class and teacher:**
1. "Are my four research questions specific enough, or should two be merged?" (`docs/research_questions.md`)
2. "Is a 90% agreement threshold sensible when the reference labels come from AI judges?"
3. "Is clustering a good independent check for a rule-based classifier?"

## Likely questions

- *"How do you know the classification is right?"* I measured it: 98% agreement with independent AI labellers on clear rows, from a fresh sample. Not ground truth. Next, a human check of disagreements and a clustering check.
- *"Isn't an IP address personal data?"* Yes, so the IP is hashed with a secret salt before analysis. Only an anonymised sample and totals are committed or shown. Raw logs stay out of git and out of AI chats.
- *"Why not just block the scanners?"* The data shows what to block: the exposed files first (done, -98% outgoing data), and I'm looking at only accepting traffic from Cloudflare.
- *"Why are there more requests after the fix?"* Scanners don't notice that the files are gone. They keep asking, but now get a refusal.
- *"Why is 'human' so small?"* It is a small personal site, and most traffic is automated. The classifier only calls a request human when it looks like a real browser on a normal page.

## After the session

Type the feedback into KAP-19 right away.
