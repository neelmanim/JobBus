import { createClient } from '@supabase/supabase-js';

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL || '';
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY || '';

// Allow app to render even without Supabase credentials (dev mode)
const hasCredentials = supabaseUrl && supabaseAnonKey;

export const supabase = hasCredentials
  ? createClient(supabaseUrl, supabaseAnonKey)
  : null;

export const isDemoMode = !hasCredentials;
