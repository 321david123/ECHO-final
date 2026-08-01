-- ECHO migration 014: "Invita y Gana" — sistema de referidos (evento regreso a clases)
--
-- Escalera de premios (referidos COMPLETADOS = amig@ registrad@ + su primer echo):
--   *  1 → Badge OG 🐿️ (emoji exclusivo de avatar; digital, se desbloquea en la app)
--   *  5 → Perfil dorado ✨ (color de avatar exclusivo; digital y OPCIONAL — el usuario
--          elige si lo usa; no se aplica solo)
--   * 10 → Bebida Starbucks / Tim Hortons ☕️ — SE REPITE cada 10 (20 = 2ª, 30 = 3ª…)
--
-- Evento LIMITADO de lanzamiento: OG y dorado son legacy — quien los gana los conserva
-- para siempre; al terminar el evento nadie más los podrá conseguir.
--
-- Solo las bebidas necesitan entrega física: quedan en referral_rewards para que el
-- admin las entregue y marque 'delivered'. Los premios digitales se derivan del conteo
-- de completados en la app (no requieren fila).
--
-- Autocontenida: crea app_config/config_text si no aplicaste la migración 009.
-- Todas las notificaciones van por push_notification_queue (ya existente) y están
-- envueltas en EXCEPTION para que un fallo de notificación NUNCA bloquee un post.
-- Correr en SQL Editor.

-- ---------------------------------------------------------------------------
-- 0) Config (idéntica a 009; segura si 009 no está aplicada)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_config (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.config_text(p_key TEXT, p_default TEXT DEFAULT NULL)
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE((SELECT value FROM public.app_config WHERE key = p_key), p_default);
$$;

-- Referidos completados por cada bebida (premio repetible). La app muestra 10;
-- si cambias esto, cambia también `referralsPerDrink` en AppState.swift.
DELETE FROM public.app_config WHERE key = 'referrals_per_reward';  -- clave de una versión previa
INSERT INTO public.app_config (key, value) VALUES
  ('referrals_per_drink', '10')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 1) Código de referido en profiles
-- ---------------------------------------------------------------------------
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS referral_code TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_profiles_referral_code
  ON public.profiles(referral_code) WHERE referral_code IS NOT NULL;

-- 6 caracteres, sin O/0/I/1 para que se dicte fácil.
CREATE OR REPLACE FUNCTION public.generate_referral_code()
RETURNS TEXT
LANGUAGE plpgsql
VOLATILE
AS $$
DECLARE
  v_alphabet CONSTANT TEXT := 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  v_code TEXT;
BEGIN
  LOOP
    v_code := '';
    FOR i IN 1..6 LOOP
      v_code := v_code || substr(v_alphabet, 1 + floor(random() * length(v_alphabet))::int, 1);
    END LOOP;
    EXIT WHEN NOT EXISTS (SELECT 1 FROM public.profiles WHERE referral_code = v_code);
  END LOOP;
  RETURN v_code;
END;
$$;

-- Asignar código al crear (o si por alguna razón quedó NULL en un update).
CREATE OR REPLACE FUNCTION public.assign_referral_code()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  IF NEW.referral_code IS NULL THEN
    NEW.referral_code := public.generate_referral_code();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_profiles_referral_code ON public.profiles;
CREATE TRIGGER tr_profiles_referral_code
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.assign_referral_code();

-- Backfill para usuarios existentes.
UPDATE public.profiles SET referral_code = public.generate_referral_code()
WHERE referral_code IS NULL;

-- ---------------------------------------------------------------------------
-- 2) Tabla referrals — un referidor por usuario, nunca a ti mismo
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referrals (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referred_id UUID NOT NULL UNIQUE REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at TIMESTAMPTZ,
  CONSTRAINT referrals_no_self CHECK (referrer_id <> referred_id)
);

CREATE INDEX IF NOT EXISTS idx_referrals_referrer ON public.referrals(referrer_id, status);

ALTER TABLE public.referrals ENABLE ROW LEVEL SECURITY;

-- Solo lectura de tus propias filas (como invitador o invitado).
-- Escritura únicamente vía funciones SECURITY DEFINER (sin políticas de INSERT/UPDATE).
DROP POLICY IF EXISTS "referrals participants can view" ON public.referrals;
CREATE POLICY "referrals participants can view"
  ON public.referrals FOR SELECT
  USING (auth.uid() = referrer_id OR auth.uid() = referred_id);

-- ---------------------------------------------------------------------------
-- 3) Premios físicos (bebidas) — 1 fila cada 10 completados; admin marca 'delivered'
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.referral_rewards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  referral_count_at_award INT NOT NULL,
  status TEXT NOT NULL DEFAULT 'earned' CHECK (status IN ('earned', 'delivered')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_referral_rewards_user ON public.referral_rewards(user_id);

ALTER TABLE public.referral_rewards ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "rewards owner can view" ON public.referral_rewards;
CREATE POLICY "rewards owner can view"
  ON public.referral_rewards FOR SELECT
  USING (auth.uid() = user_id);
-- Sin políticas de escritura: solo triggers (definer) y tú desde el dashboard.

-- ---------------------------------------------------------------------------
-- 4) Núcleo compartido: completar un referido + escalera de premios
--    1 → badge OG · 5 → perfil dorado · cada 10 → bebida (repetible)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.referral_mark_completed(p_referral_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_referrer UUID;
  v_completed INT;
  v_per_drink INT;
  v_admin UUID;
  v_title TEXT;
  v_body TEXT;
  v_kind TEXT;
BEGIN
  UPDATE public.referrals
     SET status = 'completed', completed_at = now()
   WHERE id = p_referral_id AND status = 'pending'
   RETURNING referrer_id INTO v_referrer;

  IF v_referrer IS NULL THEN
    RETURN;  -- ya estaba completado o no existe
  END IF;

  SELECT count(*) INTO v_completed
    FROM public.referrals
   WHERE referrer_id = v_referrer AND status = 'completed';

  v_per_drink := COALESCE(NULLIF(public.config_text('referrals_per_drink', '10'), '')::int, 10);
  IF v_per_drink < 1 THEN v_per_drink := 10; END IF;

  -- Copy según el hito alcanzado.
  IF v_completed = 1 THEN
    v_kind := 'referral_og_badge';
    v_title := '🐿️ ¡Badge OG desbloqueado!';
    v_body := 'Tu amig@ publicó su primer echo. Eres de los primeros OGs de Echo — el squirrel te espera en Perfil → Editar perfil (úsalo si quieres, es tuyo para siempre).';
  ELSIF v_completed = 5 THEN
    v_kind := 'referral_gold_profile';
    v_title := '✨ ¡Perfil dorado desbloqueado!';
    v_body := 'Ya son 5 referidos. El color dorado es tuyo para siempre — actívalo si quieres en Perfil → Editar perfil. Vas 5/' || v_per_drink || ' para tu bebida ☕️';
  ELSIF v_completed % v_per_drink = 0 THEN
    v_kind := 'referral_reward';
    v_title := '☕️ ¡GANASTE UNA BEBIDA!';
    v_body := 'Llegaste a ' || v_completed || ' referidos. El equipo de Echo te contactará para entregarte tu bebida de Starbucks o Tim Hortons 🎉';
  ELSIF v_completed < 5 THEN
    v_kind := 'referral_completed';
    v_title := '☕️ +1 referido';
    v_body := 'Tu amig@ ya publicó su primer echo. Llevas ' || v_completed || '/5 para el perfil dorado ✨';
  ELSE
    v_kind := 'referral_completed';
    v_title := '☕️ +1 referido';
    v_body := 'Tu amig@ ya publicó su primer echo. Llevas ' || (v_completed % v_per_drink) || '/' || v_per_drink ||
              CASE WHEN v_completed > v_per_drink THEN ' para tu próxima bebida.' ELSE ' para tu bebida.' END;
  END IF;

  BEGIN
    INSERT INTO public.push_notification_queue (user_id, kind, title, body, payload)
    VALUES (v_referrer, v_kind, v_title, v_body,
            jsonb_build_object('kind', v_kind, 'completed', v_completed));
  EXCEPTION WHEN OTHERS THEN NULL; END;

  -- Bebida cada v_per_drink completados (única con entrega física).
  IF v_completed % v_per_drink = 0 THEN
    INSERT INTO public.referral_rewards (user_id, referral_count_at_award)
    VALUES (v_referrer, v_completed);

    -- Avisar al admin para que entregue el premio (usa admin_user_id de app_config si existe).
    BEGIN
      v_admin := NULLIF(public.config_text('admin_user_id', ''), '')::uuid;
      IF v_admin IS NOT NULL AND v_admin <> v_referrer THEN
        INSERT INTO public.push_notification_queue (user_id, kind, title, body, payload)
        VALUES (
          v_admin,
          'referral_reward_admin',
          '🏆 Bebida de referidos ganada',
          'Un usuario llegó a ' || v_completed || ' referidos. Revisa referral_rewards para entregarla.',
          jsonb_build_object('kind', 'referral_reward_admin', 'user_id', v_referrer, 'completed', v_completed)
        );
      END IF;
    EXCEPTION WHEN OTHERS THEN NULL; END;
  END IF;
END;
$$;

-- ---------------------------------------------------------------------------
-- 5) RPC: asegurar/obtener mi código (la app lo llama al cargar el perfil)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_referral_code()
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_code TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  SELECT referral_code INTO v_code FROM public.profiles WHERE id = v_uid;
  IF v_code IS NULL THEN
    v_code := public.generate_referral_code();
    UPDATE public.profiles SET referral_code = v_code WHERE id = v_uid;
  END IF;
  RETURN v_code;
END;
$$;

-- ---------------------------------------------------------------------------
-- 6) RPC: reclamar un código ("¿quién te invitó?")
--    Reglas: cuenta nueva (< 7 días), no tu propio código, solo un referidor
--    por usuario. Si el usuario ya publicó, se completa de inmediato.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.claim_referral(p_code TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_code TEXT := upper(trim(COALESCE(p_code, '')));
  v_referrer UUID;
  v_created TIMESTAMPTZ;
  v_referral_id UUID;
  v_has_post BOOLEAN;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('status', 'not_authenticated');
  END IF;
  IF length(v_code) <> 6 THEN
    RETURN jsonb_build_object('status', 'invalid_code');
  END IF;

  SELECT id INTO v_referrer FROM public.profiles WHERE referral_code = v_code;
  IF v_referrer IS NULL THEN
    RETURN jsonb_build_object('status', 'invalid_code');
  END IF;
  IF v_referrer = v_uid THEN
    RETURN jsonb_build_object('status', 'own_code');
  END IF;
  IF EXISTS (SELECT 1 FROM public.referrals WHERE referred_id = v_uid) THEN
    RETURN jsonb_build_object('status', 'already_referred');
  END IF;

  -- Solo cuentas nuevas: evita que usuarios existentes se "dejen invitar".
  SELECT created_at INTO v_created FROM auth.users WHERE id = v_uid;
  IF v_created IS NULL OR v_created < now() - interval '7 days' THEN
    RETURN jsonb_build_object('status', 'account_too_old');
  END IF;

  INSERT INTO public.referrals (referrer_id, referred_id, code)
  VALUES (v_referrer, v_uid, v_code)
  RETURNING id INTO v_referral_id;

  -- Si ya publicó su primer echo antes de meter el código, cuenta de una vez.
  SELECT EXISTS (SELECT 1 FROM public.posts WHERE author_id = v_uid) INTO v_has_post;
  IF v_has_post THEN
    PERFORM public.referral_mark_completed(v_referral_id);
    RETURN jsonb_build_object('status', 'ok', 'completed', true);
  END IF;

  RETURN jsonb_build_object('status', 'ok', 'completed', false);
END;
$$;

-- ---------------------------------------------------------------------------
-- 7) Trigger: el PRIMER post del invitado completa el referido
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.complete_referral_on_first_post()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_referral_id UUID;
BEGIN
  -- Blindado: cualquier error aquí no debe impedir publicar.
  BEGIN
    IF NEW.author_id IS NOT NULL THEN
      SELECT id INTO v_referral_id
        FROM public.referrals
       WHERE referred_id = NEW.author_id AND status = 'pending'
       LIMIT 1;
      IF v_referral_id IS NOT NULL THEN
        PERFORM public.referral_mark_completed(v_referral_id);
      END IF;
    END IF;
  EXCEPTION WHEN OTHERS THEN NULL; END;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS tr_complete_referral_on_first_post ON public.posts;
CREATE TRIGGER tr_complete_referral_on_first_post
  AFTER INSERT ON public.posts
  FOR EACH ROW EXECUTE FUNCTION public.complete_referral_on_first_post();
