# Tests never depend on a downloaded geo database: point the default at an
# empty directory so anonymise_requests() falls back to NA geo fields.
withr::local_envvar(WTA_GEO_DIR = tempfile("no-geo-"), .local_envir = teardown_env())
