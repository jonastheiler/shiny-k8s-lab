# =============================================================================
# File:    global.R
# Purpose: Runs once when the Shiny app starts, before any user session begins.
#          Sets up shared resources — in this case the database connection pool —
#          that are available to both ui.R and server.R throughout the app's lifetime.
# =============================================================================

# --- Libraries ---------------------------------------------------------------
# shiny    : the web application framework
# DBI      : a unified interface for talking to any database (like JDBC in Java)
# RPostgres: the PostgreSQL driver that DBI uses under the hood
# pool     : manages a pool of reusable DB connections (see explanation below)
# DT       : renders interactive HTML tables (DataTables.js wrapper)
# ggplot2  : declarative data visualisation

library(shiny)
library(DBI)
library(RPostgres)
library(pool)
library(DT)
library(ggplot2)

# --- Database connection pool -------------------------------------------------
# WHY a pool instead of a single connection?
#   A single dbConnect() opens one connection for the entire app. If two users
#   submit a form at the same time, the second request has to wait. A pool keeps
#   several connections open and hands them out on demand — each query borrows a
#   connection, uses it, and returns it immediately. This is the standard pattern
#   for any multi-user web application.
#
# WHY Sys.getenv() instead of hardcoded values?
#   Credentials must never appear in source code. When this app runs in
#   Kubernetes, the DB_HOST, DB_USER, and DB_PASSWORD values are injected at
#   runtime from a Kubernetes Secret and ConfigMap (see k8s/). This way the same
#   Docker image works in every environment without modification.

pool <- dbPool(
  drv      = RPostgres::Postgres(),                      # tell DBI to use the PostgreSQL driver
  host     = Sys.getenv("DB_HOST"),                      # injected from Kubernetes ConfigMap
  port     = as.integer(Sys.getenv("DB_PORT", "5432")), # default PostgreSQL port
  dbname   = Sys.getenv("DB_NAME"),                      # injected from Kubernetes ConfigMap
  user     = Sys.getenv("DB_USER"),                      # injected from Kubernetes Secret
  password = Sys.getenv("DB_PASSWORD")                   # injected from Kubernetes Secret
)

# --- Cleanup ------------------------------------------------------------------
# When the Shiny app shuts down (e.g. the container stops), gracefully close all
# connections in the pool. Without this, connections would remain open on the
# PostgreSQL side until they time out — wasting server resources.
onStop(function() poolClose(pool))
