-- Popup POS DB Schema v0.1
-- 参照: reference/スクリーンショット (2403).png

CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  role VARCHAR(16) NOT NULL CHECK (role IN ('staff','manager','admin')),
  name TEXT NOT NULL,
  pin_hash TEXT NOT NULL,
  device_ids TEXT[] DEFAULT '{}',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS products (
  prd_id SERIAL PRIMARY KEY,
  code VARCHAR(25) NOT NULL UNIQUE,
  name VARCHAR(50) NOT NULL,
  price INTEGER NOT NULL,
  tax_code CHAR(2) NOT NULL DEFAULT '10',
  barcode VARCHAR(64) UNIQUE,
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transactions (
  trd_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  datetime TIMESTAMP NOT NULL DEFAULT NOW(),
  emp_cd CHAR(10) NOT NULL,
  store_cd CHAR(5) NOT NULL,
  pos_no CHAR(3) NOT NULL,
  total_amt INTEGER NOT NULL,
  ttl_amt_ex_tax INTEGER NOT NULL,
  payment_method VARCHAR(16) NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'completed',
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS transaction_details (
  trd_id UUID NOT NULL REFERENCES transactions(trd_id) ON DELETE CASCADE,
  dtl_id SERIAL NOT NULL,
  prd_id INTEGER REFERENCES products(prd_id),
  prd_code CHAR(13),
  prd_name VARCHAR(50) NOT NULL,
  prd_price INTEGER NOT NULL,
  quantity INTEGER NOT NULL,
  tax_cd CHAR(2) NOT NULL,
  discount INTEGER DEFAULT 0,
  PRIMARY KEY (trd_id, dtl_id)
);

CREATE TABLE IF NOT EXISTS offline_queue (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  device_id TEXT NOT NULL,
  payload JSONB NOT NULL,
  status VARCHAR(16) NOT NULL DEFAULT 'pending',
  last_error TEXT,
  created_at TIMESTAMP NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS audit_logs (
  id BIGSERIAL PRIMARY KEY,
  actor_id UUID,
  action VARCHAR(64) NOT NULL,
  target VARCHAR(64),
  payload JSONB,
  created_at TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_transactions_datetime ON transactions(datetime DESC);
CREATE INDEX IF NOT EXISTS idx_transaction_details_prd_code ON transaction_details(prd_code);
CREATE INDEX IF NOT EXISTS idx_offline_queue_status ON offline_queue(status);
