-- =============================================================================
-- File:    init.sql
-- Purpose: Initialize the PostgreSQL database for the measurements application
-- Runs:    Runs once to create the database schema and seed initial data
-- Creates: The `measurements` table and initial data rows
-- =============================================================================

CREATE TABLE measurements (
    id               SERIAL PRIMARY KEY,
    observed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    location         TEXT        NOT NULL,
    measurement_type TEXT        NOT NULL,
    value            NUMERIC     NOT NULL,
    unit             TEXT        NOT NULL,
    observer         TEXT        NOT NULL,
    notes            TEXT
);

-- Without an index, PostgreSQL scans every row to find matching records (full table scan).
-- With this index, it can jump directly to the relevant rows using a B-tree structure.
-- DESC order matches the most common query pattern: "show me the most recent measurements first."
CREATE INDEX idx_measurements_observed_at ON measurements (observed_at DESC);

INSERT INTO measurements (observed_at, location, measurement_type, value, unit, observer, notes)
VALUES
    ('2026-09-01 08:30:00+02', 'Lake Constance - North Shore', 'pH', 7.4, 'pH', 'J. Theiler', 'Clear morning, low wind'),
    ('2026-09-01 08:45:00+02', 'Lake Constance - North Shore', 'Temperature', 18.5, '°C', 'J. Theiler', 'Water temperature measured at 0.5m depth'),
    ('2026-09-01 09:00:00+02', 'Lake Constance - North Shore', 'Dissolved Oxygen', 9.2, 'mg/L', 'J. Theiler', 'Measured using a portable DO meter'),
    ('2026-09-01 09:15:00+02', 'Lake Constance - North Shore', 'Turbidity', 3.5, 'NTU', 'J. Theiler', 'Water clarity measured with a Secchi disk'),
    ('2026-09-01 09:30:00+02', 'Lake Constance - North Shore', 'Conductivity', 450, 'µS/cm', 'J. Theiler', 'Measured with a handheld conductivity meter')
;