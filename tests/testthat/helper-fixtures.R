fixture_path <- function(name) testthat::test_path("fixtures", name)

fixture_requests <- function() {
  raw <- read_raw_log(fixture_path("mini.json.log"))
  parse_access_log(raw$line[raw$stream == "stdout"])
}
