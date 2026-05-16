-- =============================================================
-- JobBus — Migration 003: UNIQUE constraint on opportunities(user_id, job_url)
--
-- REQUIRED for upsert(on_conflict="user_id,job_url") to work.
-- Without this the Supabase upsert will throw a 409/42P10 error
-- because Postgres can only resolve conflicts on constraint columns.
--
-- Safe to run multiple times (IF NOT EXISTS guard).
-- Run this in Supabase SQL Editor.
-- =============================================================

-- 1. Remove any fully-duplicate rows first (keep the most recent one)
--    so we don't hit a unique-constraint violation during index creation.
DELETE FROM opportunities
WHERE id IN (
    SELECT id FROM (
        SELECT id,
               ROW_NUMBER() OVER (
                   PARTITION BY user_id, job_url
                   ORDER BY created_at DESC
               ) AS rn
        FROM opportunities
        WHERE job_url IS NOT NULL
    ) t
    WHERE rn > 1
);

-- 2. Add the UNIQUE constraint (idempotent via IF NOT EXISTS)
ALTER TABLE opportunities
    ADD CONSTRAINT uq_opportunities_user_job_url
    UNIQUE (user_id, job_url);

-- 3. Verify
--    SELECT indexname FROM pg_indexes
--    WHERE tablename = 'opportunities'
--    ORDER BY indexname;
