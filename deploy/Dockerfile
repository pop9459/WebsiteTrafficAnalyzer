# KAP-60: nightly analysis pipeline (logs -> dashboard JSON).
# Build from the repo root:  docker build -f deploy/Dockerfile -t wta-analyzer:dev .
# The salt and the geo databases are NOT part of the image; they are mounted at run time.

# ---- stage 1: build the R library with the pinned packages -------------------
FROM rocker/r-ver:4.6.1 AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libssl-dev libcurl4-openssl-dev libxml2-dev libicu-dev zlib1g-dev \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /build
# Dependency layer first, so code changes do not trigger a full package rebuild.
COPY renv.lock renv.lock
RUN mkdir -p /opt/rlib \
 && Rscript -e 'install.packages("renv", repos = "https://packagemanager.posit.co/cran/latest")' \
 && Rscript -e 'renv::restore(lockfile = "renv.lock", library = "/opt/rlib", prompt = FALSE, clean = FALSE)'
# Then the package itself (R/ only; tests, data and docs stay out).
COPY DESCRIPTION NAMESPACE LICENSE ./
COPY R/ R/
RUN R CMD INSTALL --no-docs --no-test-load --library=/opt/rlib . \
 && find /opt/rlib -name '*.so' -exec strip --strip-unneeded {} + 2>/dev/null || true \
 && rm -rf /opt/rlib/*/doc /opt/rlib/*/help /opt/rlib/*/html /opt/rlib/*/tests

# ---- stage 2: slim runtime ---------------------------------------------------
FROM rocker/r-ver:4.6.1
RUN apt-get update \
 && apt-get install -y --no-install-recommends libssl3t64 libcurl4t64 libxml2 libicu74 \
 && rm -rf /var/lib/apt/lists/* \
 && useradd --system --uid 990 --no-create-home --shell /usr/sbin/nologin wta
COPY --from=build /opt/rlib /opt/rlib
COPY deploy/pipeline.R deploy/run_pipeline.sh /app/
RUN chmod 0755 /app/run_pipeline.sh
ENV R_LIBS=/opt/rlib \
    WTA_LOG_DIR=/logs \
    WTA_OUT_FILE=/out/traffic.json \
    WTA_SALT_FILE=/run/secrets/wta_salt \
    TZ=UTC
USER wta
ENTRYPOINT ["/app/run_pipeline.sh"]
