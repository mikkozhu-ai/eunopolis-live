-- ============================================================================
-- 《经世济国》(Eunopolis) v1.1 全球真人云端天梯 — Supabase 建表与防顶号安全脚本
-- 使用方法：打开 Supabase 控制台 -> SQL Editor -> New Query -> 粘贴全文并点击 Run
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.cloud_saves (
  player_id TEXT PRIMARY KEY,
  nation_name TEXT NOT NULL CHECK (char_length(nation_name) BETWEEN 1 AND 32),
  gdp DOUBLE PRECISION NOT NULL CHECK (gdp >= 0 AND gdp <= 850000),
  quarter INTEGER NOT NULL DEFAULT 0 CHECK (quarter >= 0 AND quarter <= 100000),
  unlocked INTEGER NOT NULL DEFAULT 1 CHECK (unlocked BETWEEN 1 AND 217),
  population DOUBLE PRECISION NOT NULL DEFAULT 0,
  credit_rating TEXT NOT NULL DEFAULT 'AAA',
  ach_points INTEGER NOT NULL DEFAULT 0,
  industry_gdp JSONB NOT NULL DEFAULT '{}'::jsonb,
  save_json JSONB NOT NULL,
  secret_hash TEXT,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 兼容旧表平滑升级：补充私有凭证哈希列与常识性产值上限约束
ALTER TABLE public.cloud_saves ADD COLUMN IF NOT EXISTS secret_hash TEXT;
ALTER TABLE public.cloud_saves DROP CONSTRAINT IF EXISTS cloud_saves_gdp_plausible;
ALTER TABLE public.cloud_saves
  ADD CONSTRAINT cloud_saves_gdp_plausible
  CHECK (unlocked BETWEEN 1 AND 217 AND gdp >= 0 AND gdp <= GREATEST(260.0, unlocked::double precision * 3800.0));

CREATE INDEX IF NOT EXISTS idx_cloud_saves_gdp ON public.cloud_saves (gdp DESC);

-- 开启行级安全 (RLS)，并禁止前端直接读取 secret_hash 列或无凭证覆盖他人存档
ALTER TABLE public.cloud_saves ENABLE ROW LEVEL SECURITY;
REVOKE SELECT (secret_hash) ON public.cloud_saves FROM anon, authenticated;

DROP POLICY IF EXISTS "public_read_cloud_saves" ON public.cloud_saves;
DROP POLICY IF EXISTS "public_insert_cloud_saves" ON public.cloud_saves;
DROP POLICY IF EXISTS "public_update_cloud_saves" ON public.cloud_saves;

-- 仅开放公开只读查询；写入与更新统一走下方校验私有迁移密钥的 SECURITY DEFINER RPC
CREATE POLICY "public_read_cloud_saves"
  ON public.cloud_saves FOR SELECT
  TO anon, authenticated
  USING (true);

-- 专属迁移密钥校验写入 RPC（防止利用公开 player_id 顶号覆盖，并拦截异常数值炸榜）
CREATE OR REPLACE FUNCTION public.upsert_cloud_save(p_write_key TEXT, p_row JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pid TEXT := trim(coalesce(p_row->>'player_id', ''));
  v_hash TEXT;
  v_old_hash TEXT;
  v_gdp DOUBLE PRECISION := coalesce((p_row->>'gdp')::double precision, 0);
  v_unlocked INTEGER := coalesce((p_row->>'unlocked')::integer, 1);
  v_quarter INTEGER := coalesce((p_row->>'quarter')::integer, 0);
BEGIN
  IF char_length(p_write_key) < 12 OR char_length(p_write_key) > 80 THEN
    RAISE EXCEPTION 'invalid write key';
  END IF;
  IF char_length(v_pid) < 6 OR char_length(v_pid) > 64 THEN
    RAISE EXCEPTION 'invalid player_id';
  END IF;
  IF octet_length((p_row->'save_json')::text) > 409600 THEN
    RAISE EXCEPTION 'save_json too large';
  END IF;
  IF v_unlocked < 1 OR v_unlocked > 217 OR v_gdp < 0 OR v_gdp > GREATEST(260.0, v_unlocked::double precision * 3800.0) THEN
    RAISE EXCEPTION 'implausible gdp for unlocked tiles';
  END IF;

  v_hash := md5('euno_v11_secret:' || trim(p_write_key));
  SELECT secret_hash INTO v_old_hash FROM public.cloud_saves WHERE player_id = v_pid;
  IF FOUND AND v_old_hash IS NOT NULL AND v_old_hash <> v_hash THEN
    RAISE EXCEPTION 'write credential mismatch for player_id';
  END IF;

  INSERT INTO public.cloud_saves (
    player_id, nation_name, gdp, quarter, unlocked, population,
    credit_rating, ach_points, industry_gdp, save_json, secret_hash, updated_at
  ) VALUES (
    v_pid,
    left(coalesce(p_row->>'nation_name', '未命名国家'), 32),
    v_gdp,
    v_quarter,
    v_unlocked,
    coalesce((p_row->>'population')::double precision, 0),
    coalesce(p_row->>'credit_rating', 'AAA'),
    coalesce((p_row->>'ach_points')::integer, 0),
    coalesce(p_row->'industry_gdp', '{}'::jsonb),
    p_row->'save_json',
    v_hash,
    NOW()
  )
  ON CONFLICT (player_id) DO UPDATE SET
    nation_name = EXCLUDED.nation_name,
    gdp = EXCLUDED.gdp,
    quarter = EXCLUDED.quarter,
    unlocked = EXCLUDED.unlocked,
    population = EXCLUDED.population,
    credit_rating = EXCLUDED.credit_rating,
    ach_points = EXCLUDED.ach_points,
    industry_gdp = EXCLUDED.industry_gdp,
    save_json = EXCLUDED.save_json,
    secret_hash = COALESCE(public.cloud_saves.secret_hash, EXCLUDED.secret_hash),
    updated_at = NOW();
END;
$$;

GRANT EXECUTE ON FUNCTION public.upsert_cloud_save(TEXT, JSONB) TO anon, authenticated;
