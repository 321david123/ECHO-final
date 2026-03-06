-- Custom OTP codes (our flow: request-otp stores code, verify-otp checks and exchanges for Supabase session)
CREATE TABLE IF NOT EXISTS public.otp_codes (
  email TEXT NOT NULL,
  code TEXT NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (email)
);

-- Only Edge Functions (service role) access this table. No policies = anon/auth get no rows; service_role bypasses RLS.
ALTER TABLE public.otp_codes ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.otp_codes IS 'One-time codes for custom OTP auth; used by request-otp and verify-otp Edge Functions (service_role).';
