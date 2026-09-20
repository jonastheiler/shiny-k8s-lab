# =============================================================================
# File:    Dockerfile
# Purpose: Defines the container image for the R Shiny application.
#          Docker reads this file top-to-bottom and executes each instruction
#          as a layer. Layers are cached — if a layer has not changed, Docker
#          reuses the cached version, making rebuilds fast.
#
# Base image: rocker/shiny
#   The Rocker project maintains production-grade R Docker images.
#   rocker/shiny bundles R + the Shiny Server daemon, saving us from
#   installing and configuring Shiny Server ourselves.
# =============================================================================

FROM rocker/shiny:latest

# -----------------------------------------------------------------------------
# LABEL — metadata about this image (visible in 'docker inspect')
# Good practice for portfolio / team projects.
# -----------------------------------------------------------------------------
LABEL maintainer="Jonas Theiler <jonas_theiler@hotmail.com>"
LABEL description="Field Measurement Logger — R Shiny app backed by PostgreSQL"
LABEL project="shiny-k8s-lab"

# -----------------------------------------------------------------------------
# SYSTEM DEPENDENCIES
# RPostgres links against the PostgreSQL C client library (libpq).
# Without libpq-dev, install.packages("RPostgres") will fail at compile time.
#
# We install in a single RUN instruction to keep the layer count low.
# `apt-get clean` and `rm -rf /var/lib/apt/lists/*` remove the package cache
# so the image stays as small as possible.
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    libssl-dev \
    libcurl4-openssl-dev \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# -----------------------------------------------------------------------------
# R PACKAGE INSTALLATION
# We install all required packages in one RUN layer.
#
# Why Ncpus = parallel::detectCores()?
#   R compiles packages from source in this image. Using all available CPU
#   cores speeds up the build significantly (DBI + RPostgres take ~2 minutes
#   on a single core; a few seconds with 4+).
#
# Why repos = "https://packagemanager.posit.co/cran/__linux__/jammy/latest"?
#   Posit Package Manager (PPM) provides pre-compiled binary packages for
#   Ubuntu 22.04 (Jammy). Binaries install in seconds vs. minutes from source.
# -----------------------------------------------------------------------------
RUN R -e "\
  options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest')); \
  install.packages(c( \
    'shiny',     \
    'DBI',       \
    'RPostgres', \
    'pool',      \
    'DT',        \
    'ggplot2'    \
  ), Ncpus = parallel::detectCores()) \
"

# -----------------------------------------------------------------------------
# APPLICATION FILES
# Copy the three Shiny app files into the directory that Shiny Server
# watches by default: /srv/shiny-server/
#
# We copy the files individually (not the whole directory) so that changing
# one file does not invalidate the cache for the others.
# -----------------------------------------------------------------------------
COPY global.R  /srv/shiny-server/global.R
COPY ui.R      /srv/shiny-server/ui.R
COPY server.R  /srv/shiny-server/server.R

# -----------------------------------------------------------------------------
# PERMISSIONS
# By default, Shiny Server runs as the 'shiny' user (UID 999).
# We ensure the app files and log directory are readable/writable by that user.
# This also makes the image compatible with Kubernetes security contexts that
# run containers as a non-root user.
# -----------------------------------------------------------------------------
RUN chown -R shiny:shiny /srv/shiny-server \
    && chmod -R 755 /srv/shiny-server \
    && mkdir -p /var/log/shiny-server \
    && chown -R shiny:shiny /var/log/shiny-server

# -----------------------------------------------------------------------------
# PORT
# Shiny Server listens on port 3838 by default.
# EXPOSE is documentation — it tells Docker and Kubernetes which port the
# container uses, but does not actually publish it to the host.
# Publishing happens in the Kubernetes Service manifest (k8s/shiny/07-service.yaml).
# -----------------------------------------------------------------------------
EXPOSE 3838

# -----------------------------------------------------------------------------
# USER
# Run as the non-root 'shiny' user for security.
# Running as root inside a container is a security risk — if the app is
# compromised, an attacker would have root access to the container.
# -----------------------------------------------------------------------------
USER shiny

# -----------------------------------------------------------------------------
# CMD
# The base rocker/shiny image already sets a CMD to start Shiny Server.
# We do not override it here — the inherited CMD is:
#   CMD ["/usr/bin/shiny-server"]
# -----------------------------------------------------------------------------
