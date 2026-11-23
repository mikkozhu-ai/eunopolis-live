-- 《经世济国》v1.0 正式版 Supabase 云端天梯建表与正式服清榜脚本
-- 使用方式：在正式版 1.0 发布上线时，打开 Supabase Dashboard -> SQL Editor 运行即可。

-- 【可选·正式版上线清榜】：清空 0.9 内测期旧快照与完全体测试档（取消下一行注释后执行）
-- TRUNCATE TABLE public.cloud_saves;

CREATE TABLE IF NOT EXISTS public.cloud_saves (
  player_id TEXT PRIMARY KEY,
  nation_name TEXT NOT NULL CHECK (char_length(nation_name) BETWEEN 1 AND 32),
  gdp DOUBLE PRECISION NOT NULL CHECK (gdp >= 0 AND gdp < 1e9),
  quarter INTEGER NOT NULL DEFAULT 0,
  unlocked INTEGER NOT NULL DEFAULT 1,
  population DOUBLE PRECISION NOT NULL DEFAULT 0,
  credit_rating TEXT NOT NULL DEFAULT 'AAA',
  ach_points INTEGER NOT NULL DEFAULT 0,
  industry_gdp JSONB NOT NULL DEFAULT '{}'::jsonb,
  save_json JSONB NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cloud_saves_gdp ON public.cloud_saves (gdp DESC);

ALTER TABLE public.cloud_saves ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cloud_saves' AND policyname = 'public_read_cloud_saves') THEN
    CREATE POLICY "public_read_cloud_saves" ON public.cloud_saves FOR SELECT TO anon, authenticated USING (true);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cloud_saves' AND policyname = 'public_insert_cloud_saves') THEN
    CREATE POLICY "public_insert_cloud_saves" ON public.cloud_saves FOR INSERT TO anon, authenticated
      WITH CHECK (char_length(player_id) BETWEEN 6 AND 64 AND octet_length(save_json::text) <= 524288);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'cloud_saves' AND policyname = 'public_update_cloud_saves') THEN
    CREATE POLICY "public_update_cloud_saves" ON public.cloud_saves FOR UPDATE TO anon, authenticated
      USING (char_length(player_id) BETWEEN 6 AND 64)
      WITH CHECK (char_length(player_id) BETWEEN 6 AND 64 AND octet_length(save_json::text) <= 524288);
  END IF;
END $$;
