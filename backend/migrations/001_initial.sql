-- =============================================================
-- JobBus — Initial Database Schema (Supabase PostgreSQL)
-- Run this in Supabase SQL Editor
-- =============================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ═══════════════════════════════════════════════════════════════
-- USER PROFILES
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS user_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT UNIQUE NOT NULL,  -- Supabase auth.users id
    email TEXT NOT NULL,
    display_name TEXT NOT NULL DEFAULT '',
    avatar_url TEXT,
    mode TEXT NOT NULL DEFAULT 'beginner' CHECK (mode IN ('beginner', 'advanced')),
    is_admin BOOLEAN NOT NULL DEFAULT FALSE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_user_profiles_user_id ON user_profiles(user_id);

-- ═══════════════════════════════════════════════════════════════
-- INVITE CODES
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS invites (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    code TEXT UNIQUE NOT NULL,
    created_by TEXT NOT NULL,
    used BOOLEAN NOT NULL DEFAULT FALSE,
    used_by TEXT,
    used_at TIMESTAMPTZ,
    note TEXT,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invites_code ON invites(code);

-- ═══════════════════════════════════════════════════════════════
-- USER SECRETS (Encrypted)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS user_secrets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT UNIQUE NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    gemini_key_encrypted TEXT,
    jsearch_key_encrypted TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- SMTP CREDENTIALS (Encrypted)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS smtp_credentials (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT UNIQUE NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    smtp_host TEXT NOT NULL DEFAULT 'smtp.gmail.com',
    smtp_port INTEGER NOT NULL DEFAULT 587,
    smtp_user TEXT NOT NULL,
    smtp_pass_encrypted TEXT NOT NULL,
    sender_name TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- RESUME PROFILES
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS resume_profiles (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT UNIQUE NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    name TEXT NOT NULL DEFAULT '',
    role TEXT NOT NULL DEFAULT '',
    skills JSONB NOT NULL DEFAULT '[]'::JSONB,
    achievements JSONB NOT NULL DEFAULT '[]'::JSONB,
    email_context TEXT NOT NULL DEFAULT '',
    file_path TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════════
-- OPPORTUNITIES
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS opportunities (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    company_name TEXT NOT NULL,
    role_title TEXT NOT NULL DEFAULT '',
    job_url TEXT,
    score REAL NOT NULL DEFAULT 0,
    tier TEXT NOT NULL DEFAULT 'low' CHECK (tier IN ('high', 'medium', 'low')),
    signals JSONB NOT NULL DEFAULT '{}'::JSONB,
    recommended_angle TEXT,
    status TEXT NOT NULL DEFAULT 'discovered' CHECK (status IN (
        'discovered', 'reviewing', 'approved', 'outreach_sent', 'replied', 'interview', 'rejected', 'archived'
    )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_opportunities_user_id ON opportunities(user_id);
CREATE INDEX idx_opportunities_tier ON opportunities(tier);
CREATE INDEX idx_opportunities_score ON opportunities(score DESC);

-- ═══════════════════════════════════════════════════════════════
-- CONTACTS
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    opportunity_id UUID REFERENCES opportunities(id) ON DELETE SET NULL,
    first_name TEXT NOT NULL DEFAULT '',
    last_name TEXT NOT NULL DEFAULT '',
    email TEXT NOT NULL,
    title TEXT NOT NULL DEFAULT '',
    company TEXT NOT NULL DEFAULT '',
    linkedin_url TEXT,
    persona_type TEXT NOT NULL DEFAULT 'other',
    source TEXT NOT NULL DEFAULT 'manual',
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_contacts_user_id ON contacts(user_id);
CREATE INDEX idx_contacts_email ON contacts(email);

-- ═══════════════════════════════════════════════════════════════
-- CAMPAIGNS
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS campaigns (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN (
        'draft', 'reviewing', 'approved', 'sending', 'paused', 'completed', 'cancelled'
    )),
    opportunity_id UUID REFERENCES opportunities(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_campaigns_user_id ON campaigns(user_id);
CREATE INDEX idx_campaigns_status ON campaigns(status);

-- ═══════════════════════════════════════════════════════════════
-- CAMPAIGN CONTACTS (join table)
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS campaign_contacts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    campaign_id UUID NOT NULL REFERENCES campaigns(id) ON DELETE CASCADE,
    contact_id UUID NOT NULL REFERENCES contacts(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
        'pending', 'drafting', 'ready', 'sent', 'replied', 'bounced', 'interview', 'no_response'
    )),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(campaign_id, contact_id)
);

CREATE INDEX idx_campaign_contacts_campaign ON campaign_contacts(campaign_id);

-- ═══════════════════════════════════════════════════════════════
-- EMAIL DRAFTS
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS email_drafts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    campaign_id UUID REFERENCES campaigns(id) ON DELETE SET NULL,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    subject TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    angle_type TEXT,
    angle_reasoning TEXT,
    signals_used JSONB NOT NULL DEFAULT '[]'::JSONB,
    quality_score REAL,
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'approved', 'sent', 'failed')),
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_email_drafts_user_id ON email_drafts(user_id);
CREATE INDEX idx_email_drafts_campaign ON email_drafts(campaign_id);

-- ═══════════════════════════════════════════════════════════════
-- FOLLOW-UPS
-- ═══════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS follow_ups (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id TEXT NOT NULL REFERENCES user_profiles(user_id) ON DELETE CASCADE,
    initial_draft_id UUID REFERENCES email_drafts(id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts(id) ON DELETE SET NULL,
    subject TEXT NOT NULL DEFAULT '',
    body TEXT NOT NULL DEFAULT '',
    sequence INTEGER NOT NULL DEFAULT 1 CHECK (sequence IN (1, 2)),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'cancelled')),
    scheduled_at TIMESTAMPTZ NOT NULL,
    sent_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_follow_ups_status ON follow_ups(status);
CREATE INDEX idx_follow_ups_scheduled ON follow_ups(scheduled_at);

-- ═══════════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════════

-- Enable RLS on all user-facing tables
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_secrets ENABLE ROW LEVEL SECURITY;
ALTER TABLE smtp_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE resume_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE opportunities ENABLE ROW LEVEL SECURITY;
ALTER TABLE contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaigns ENABLE ROW LEVEL SECURITY;
ALTER TABLE campaign_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE email_drafts ENABLE ROW LEVEL SECURITY;
ALTER TABLE follow_ups ENABLE ROW LEVEL SECURITY;

-- Policies: Users can only see/modify their own data
-- (Service role key bypasses RLS — used by the backend)

CREATE POLICY "Users can view own profile"
    ON user_profiles FOR SELECT
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can update own profile"
    ON user_profiles FOR UPDATE
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can view own secrets"
    ON user_secrets FOR ALL
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can manage own SMTP credentials"
    ON smtp_credentials FOR ALL
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can view own resume"
    ON resume_profiles FOR ALL
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can manage own opportunities"
    ON opportunities FOR ALL
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can manage own contacts"
    ON contacts FOR ALL
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can manage own campaigns"
    ON campaigns FOR ALL
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can view own campaign contacts"
    ON campaign_contacts FOR SELECT
    USING (EXISTS (
        SELECT 1 FROM campaigns
        WHERE campaigns.id = campaign_contacts.campaign_id
        AND campaigns.user_id = auth.uid()::TEXT
    ));

CREATE POLICY "Users can manage own drafts"
    ON email_drafts FOR ALL
    USING (auth.uid()::TEXT = user_id);

CREATE POLICY "Users can manage own follow-ups"
    ON follow_ups FOR ALL
    USING (auth.uid()::TEXT = user_id);

-- ═══════════════════════════════════════════════════════════════
-- UPDATED_AT TRIGGER
-- ═══════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_user_profiles_updated
    BEFORE UPDATE ON user_profiles
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_campaigns_updated
    BEFORE UPDATE ON campaigns
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER trg_opportunities_updated
    BEFORE UPDATE ON opportunities
    FOR EACH ROW EXECUTE FUNCTION update_updated_at();
