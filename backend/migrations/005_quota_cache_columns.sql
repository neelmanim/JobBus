-- Migration 005: Add quota cache columns to user_profiles
-- These columns cache the Hunter/Apollo API quota response for 1 hour
-- so the Settings page can display credit consumption without burning credits.

ALTER TABLE user_profiles
  ADD COLUMN IF NOT EXISTS quota_cache      jsonb    DEFAULT NULL,
  ADD COLUMN IF NOT EXISTS quota_cache_at   timestamptz DEFAULT NULL;

COMMENT ON COLUMN user_profiles.quota_cache    IS 'Cached result from /api/settings/search-quota (TTL 1h)';
COMMENT ON COLUMN user_profiles.quota_cache_at IS 'Timestamp when quota_cache was last refreshed';
