-- =============================================================
-- JobBus — Migration 004: Add search_query column to opportunities
--
-- Enables DB-level caching of job search results per user+query.
-- Before hitting the Remotive/JSearch API, the backend checks
-- whether fresh results (< 6 hours old) already exist for this
-- user+query combination and returns them directly.
--
-- Safe to run multiple times (IF NOT EXISTS guard).
-- Run this in Supabase SQL Editor.
-- =============================================================

ALTER TABLE opportunities
    ADD COLUMN IF NOT EXISTS search_query TEXT NOT NULL DEFAULT '';

-- Index for fast cache lookups: user_id + search_query + updated_at
CREATE INDEX IF NOT EXISTS idx_opportunities_search_cache
    ON opportunities(user_id, search_query, updated_at DESC);
