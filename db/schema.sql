-- Aplikasi Pencatatan Keuangan untuk Bisnis UMKM: skema PostgreSQL (nominal rupiah, BIGINT)
CREATE TABLE businesses (            -- satu baris per UMKM yang mendaftar
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    business_type  TEXT,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE users (
    id             BIGSERIAL PRIMARY KEY,
    business_id    BIGINT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name           TEXT NOT NULL,
    email          TEXT NOT NULL,
    password_hash  TEXT NOT NULL,       -- simpan hasil password_hash(), jangan kata sandi asli
    role           TEXT NOT NULL DEFAULT 'pemilik' CHECK (role IN ('pemilik', 'staf')),
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (id, business_id)
);
CREATE UNIQUE INDEX uq_users_email ON users (lower(email));

CREATE TABLE accounts (              -- kas, rekening, e-wallet usaha
    id               BIGSERIAL PRIMARY KEY,
    business_id      BIGINT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    initial_balance  BIGINT NOT NULL DEFAULT 0,
    UNIQUE (business_id, name),
    UNIQUE (id, business_id)
);

CREATE TABLE categories (
    id           BIGSERIAL PRIMARY KEY,
    business_id  BIGINT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    grp          TEXT NOT NULL CHECK (grp IN ('penjualan', 'pendapatan_lain', 'modal', 'hpp', 'operasional', 'prive')),
    kind         TEXT GENERATED ALWAYS AS (CASE WHEN grp IN ('penjualan', 'pendapatan_lain', 'modal')
                                                THEN 'masuk' ELSE 'keluar' END) STORED,
    UNIQUE (business_id, name),
    UNIQUE (id, business_id),
    UNIQUE (id, business_id, kind)
);

CREATE TABLE incomes (          -- pemasukan
    id           BIGSERIAL PRIMARY KEY,
    business_id  BIGINT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    account_id   BIGINT NOT NULL,
    category_id  BIGINT NOT NULL,
    user_id      BIGINT NOT NULL,
    kind         TEXT NOT NULL DEFAULT 'masuk' CHECK (kind = 'masuk'),
    amount       BIGINT NOT NULL CHECK (amount > 0),
    note         TEXT,
    occurred_on  DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- akun, kategori, dan pencatat harus dari usaha yang sama
    FOREIGN KEY (account_id, business_id)        REFERENCES accounts (id, business_id),
    FOREIGN KEY (category_id, business_id, kind) REFERENCES categories (id, business_id, kind),
    FOREIGN KEY (user_id, business_id)           REFERENCES users (id, business_id)
);

CREATE TABLE expenses (          -- pengeluaran
    id           BIGSERIAL PRIMARY KEY,
    business_id  BIGINT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    account_id   BIGINT NOT NULL,
    category_id  BIGINT NOT NULL,
    user_id      BIGINT NOT NULL,
    kind         TEXT NOT NULL DEFAULT 'keluar' CHECK (kind = 'keluar'),
    amount       BIGINT NOT NULL CHECK (amount > 0),
    note         TEXT,
    occurred_on  DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- akun, kategori, dan pencatat harus dari usaha yang sama
    FOREIGN KEY (account_id, business_id)        REFERENCES accounts (id, business_id),
    FOREIGN KEY (category_id, business_id, kind) REFERENCES categories (id, business_id, kind),
    FOREIGN KEY (user_id, business_id)           REFERENCES users (id, business_id)
);

CREATE TABLE budgets (
    id            BIGSERIAL PRIMARY KEY,
    business_id   BIGINT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    category_id   BIGINT NOT NULL,
    month         DATE NOT NULL CHECK (EXTRACT(DAY FROM month) = 1),
    limit_amount  BIGINT NOT NULL CHECK (limit_amount > 0),
    UNIQUE (business_id, category_id, month),
    FOREIGN KEY (category_id, business_id) REFERENCES categories (id, business_id) ON DELETE CASCADE
);

CREATE TABLE recommendations (
    id           BIGSERIAL PRIMARY KEY,
    business_id  BIGINT NOT NULL REFERENCES businesses(id) ON DELETE CASCADE,
    month        DATE NOT NULL,
    rule_code    TEXT NOT NULL,       -- mis. 'anggaran_lewat', 'margin_tipis'
    severity     TEXT NOT NULL CHECK (severity IN ('info', 'peringatan', 'bahaya')),
    message      TEXT NOT NULL,
    status       TEXT NOT NULL DEFAULT 'baru' CHECK (status IN ('baru', 'selesai', 'diabaikan')),
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (business_id, month, rule_code, message)
);

CREATE INDEX idx_incomes_date ON incomes (business_id, occurred_on);
CREATE INDEX idx_expenses_date ON expenses (business_id, occurred_on);

CREATE VIEW v_arus_kas AS
SELECT business_id, account_id, category_id, occurred_on, amount AS masuk, 0::bigint AS keluar FROM incomes
UNION ALL
SELECT business_id, account_id, category_id, occurred_on, 0::bigint, amount FROM expenses;

-- Laba rugi bulanan (modal dan prive tidak dihitung sebagai laba atau beban)
CREATE VIEW v_laba_rugi AS
SELECT k.business_id,
       date_trunc('month', k.occurred_on)::date AS bulan,
       COALESCE(SUM(k.masuk)  FILTER (WHERE c.grp = 'penjualan'), 0)       AS penjualan,
       COALESCE(SUM(k.keluar) FILTER (WHERE c.grp = 'hpp'), 0)             AS hpp,
       COALESCE(SUM(k.keluar) FILTER (WHERE c.grp = 'operasional'), 0)     AS beban_operasional,
       COALESCE(SUM(k.masuk)  FILTER (WHERE c.grp = 'pendapatan_lain'), 0) AS pendapatan_lain,
       COALESCE(SUM(k.masuk - k.keluar) FILTER (WHERE c.grp NOT IN ('modal', 'prive')), 0) AS laba_bersih
FROM v_arus_kas k JOIN categories c ON c.id = k.category_id
GROUP BY k.business_id, 2;

CREATE VIEW v_saldo_akun AS
SELECT a.id AS account_id, a.business_id, a.name,
       a.initial_balance + COALESCE(SUM(k.masuk - k.keluar), 0) AS saldo
FROM accounts a LEFT JOIN v_arus_kas k ON k.account_id = a.id
GROUP BY a.id;
