-- =============================================================
-- JobBus — Migration 002: Add Missing Provider Columns
-- Run this in Supabase SQL Editor
-- Safe to run multiple times (idempotent).
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- 1. user_secrets — add all provider key columns that were
--    missing from the initial migration. Only gemini_key_encrypted
--    and jsearch_key_encrypted existed before.
-- ─────────────────────────────────────────────────────────────

ALTER TABLE user_secrets
    ADD COLUMN IF NOT EXISTS groq_key_encrypted       TEXT,
    ADD COLUMN IF NOT EXISTS openai_key_encrypted     TEXT,
    ADD COLUMN IF NOT EXISTS hunter_key_encrypted     TEXT,
    ADD COLUMN IF NOT EXISTS apollo_key_encrypted     TEXT,
    ADD COLUMN IF NOT EXISTS rocketreach_key_encrypted TEXT,
    ADD COLUMN IF NOT EXISTS ollama_base_url          TEXT;

-- ─────────────────────────────────────────────────────────────
-- 2. user_profiles — add onboarding_complete flag used by the
--    frontend route guard. Defaults to FALSE so existing users
--    are prompted to complete onboarding.
-- ─────────────────────────────────────────────────────────────

ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS onboarding_complete BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS ai_provider   TEXT NOT NULL DEFAULT 'groq',
    ADD COLUMN IF NOT EXISTS ai_model      TEXT NOT NULL DEFAULT 'auto',
    ADD COLUMN IF NOT EXISTS search_provider TEXT NOT NULL DEFAULT 'hunter',
    ADD COLUMN IF NOT EXISTS signature_name     TEXT,
    ADD COLUMN IF NOT EXISTS signature_title    TEXT,
    ADD COLUMN IF NOT EXISTS signature_linkedin TEXT,
    ADD COLUMN IF NOT EXISTS custom_instructions TEXT,
    ADD COLUMN IF NOT EXISTS send_delay_seconds  INTEGER NOT NULL DEFAULT 60,
    ADD COLUMN IF NOT EXISTS max_emails_per_day  INTEGER NOT NULL DEFAULT 50,
    ADD COLUMN IF NOT EXISTS business_hours_only BOOLEAN NOT NULL DEFAULT TRUE;

-- ─────────────────────────────────────────────────────────────
-- 3. Backfill: mark existing users as onboarding complete so
--    they don't get redirect-looped into the wizard.
-- ─────────────────────────────────────────────────────────────

UPDATE user_profiles
    SET onboarding_complete = TRUE
    WHERE onboarding_complete = FALSE
      AND created_at < NOW() - INTERVAL '1 hour';

-- ─────────────────────────────────────────────────────────────
-- 4. Verify — run this to confirm columns exist:
--    SELECT column_name FROM information_schema.columns
--    WHERE table_name IN ('user_secrets', 'user_profiles')
--    ORDER BY table_name, column_name;
-- ─────────────────────────────────────────────────────────────
