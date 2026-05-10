-- =============================================================
-- JobBus — Migration 002: Multi-Provider Architecture
-- Run this in Supabase SQL Editor AFTER 001_initial.sql
-- =============================================================

-- ─────────────────────────────────────────────────────────────
-- user_secrets: add per-provider encrypted key columns
-- ─────────────────────────────────────────────────────────────

ALTER TABLE user_secrets
    ADD COLUMN IF NOT EXISTS groq_key_encrypted       TEXT,
    ADD COLUMN IF NOT EXISTS openai_key_encrypted     TEXT,
    ADD COLUMN IF NOT EXISTS hunter_key_encrypted     TEXT,
    ADD COLUMN IF NOT EXISTS apollo_key_encrypted     TEXT,
    ADD COLUMN IF NOT EXISTS rocketreach_key_encrypted TEXT,
    ADD COLUMN IF NOT EXISTS ollama_base_url          TEXT;   -- plain URL, not encrypted

-- ─────────────────────────────────────────────────────────────
-- user_profiles: provider preferences + missing onboarding/style fields
-- ─────────────────────────────────────────────────────────────

ALTER TABLE user_profiles
    ADD COLUMN IF NOT EXISTS ai_provider TEXT NOT NULL DEFAULT 'groq'
        CHECK (ai_provider IN ('groq', 'gemini', 'openai', 'ollama')),
    ADD COLUMN IF NOT EXISTS ai_model TEXT NOT NULL DEFAULT 'auto',
    ADD COLUMN IF NOT EXISTS search_provider TEXT NOT NULL DEFAULT 'hunter'
        CHECK (search_provider IN ('hunter', 'apollo', 'rocketreach')),
    ADD COLUMN IF NOT EXISTS onboarding_complete BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS signature_name     TEXT,
    ADD COLUMN IF NOT EXISTS signature_title    TEXT,
    ADD COLUMN IF NOT EXISTS signature_linkedin TEXT,
    ADD COLUMN IF NOT EXISTS custom_instructions TEXT,
    ADD COLUMN IF NOT EXISTS style_samples      JSONB NOT NULL DEFAULT '[]'::JSONB,
    ADD COLUMN IF NOT EXISTS send_delay_seconds INTEGER NOT NULL DEFAULT 120,
    ADD COLUMN IF NOT EXISTS max_emails_per_day INTEGER NOT NULL DEFAULT 20,
    ADD COLUMN IF NOT EXISTS business_hours_only BOOLEAN NOT NULL DEFAULT TRUE;

-- ─────────────────────────────────────────────────────────────
-- campaigns: sandbox mode + outreach angle + send controls
-- ─────────────────────────────────────────────────────────────

ALTER TABLE campaigns
    ADD COLUMN IF NOT EXISTS outreach_angle     TEXT,
    ADD COLUMN IF NOT EXISTS sandbox_mode       BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS send_delay_seconds INTEGER NOT NULL DEFAULT 120,
    ADD COLUMN IF NOT EXISTS max_per_day        INTEGER NOT NULL DEFAULT 20,
    ADD COLUMN IF NOT EXISTS business_hours_only BOOLEAN NOT NULL DEFAULT TRUE;

-- ─────────────────────────────────────────────────────────────
-- contacts: enrichment metadata
-- ─────────────────────────────────────────────────────────────

ALTER TABLE contacts
    ADD COLUMN IF NOT EXISTS confidence_score REAL,
    ADD COLUMN IF NOT EXISTS search_provider  TEXT;  -- hunter | apollo | rocketreach | manual | csv

-- ─────────────────────────────────────────────────────────────
-- email_drafts: quality_issues (structured feedback list)
-- ─────────────────────────────────────────────────────────────

ALTER TABLE email_drafts
    ADD COLUMN IF NOT EXISTS quality_issues JSONB NOT NULL DEFAULT '[]'::JSONB,
    ADD COLUMN IF NOT EXISTS reply_rate_estimate REAL;  -- predicted reply rate 0-100

-- ─────────────────────────────────────────────────────────────
-- System config table (admin-managed, beginner-mode keys)
-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS system_config (
    id      UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    key     TEXT UNIQUE NOT NULL,
    value   TEXT,                       -- encrypted for secrets, plain for config
    is_secret BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Seed with placeholders (admin fills real values via Admin panel)
INSERT INTO system_config (key, is_secret) VALUES
    ('system_groq_key',    TRUE),
    ('system_hunter_key',  TRUE),
    ('max_emails_per_user_per_day', FALSE),
    ('enable_follow_ups',  FALSE),
    ('enable_ollama',      FALSE)
ON CONFLICT (key) DO NOTHING;
