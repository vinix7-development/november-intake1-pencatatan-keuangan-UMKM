-- Pencatat Keuangan Pribadi: skema awal PostgreSQL (nominal rupiah, BIGINT)
CREATE TABLE users (
    id             BIGSERIAL PRIMARY KEY,
    name           TEXT NOT NULL,
    email          TEXT NOT NULL UNIQUE,
    password_hash  TEXT NOT NULL,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE wallets (
    id               BIGSERIAL PRIMARY KEY,
    user_id          BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name             TEXT NOT NULL,
    type             TEXT NOT NULL CHECK (type IN ('tunai', 'rekening', 'ewallet')),
    initial_balance  BIGINT NOT NULL DEFAULT 0,
    UNIQUE (user_id, name),
    UNIQUE (id, user_id)
);

CREATE TABLE categories (
    id       BIGSERIAL PRIMARY KEY,
    user_id  BIGINT REFERENCES users(id) ON DELETE CASCADE,  -- NULL = kategori bawaan
    name     TEXT NOT NULL,
    kind     TEXT NOT NULL CHECK (kind IN ('income', 'expense')),
    UNIQUE (id, kind)
);

CREATE TABLE transactions (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    wallet_id     BIGINT NOT NULL,
    to_wallet_id  BIGINT,                      -- hanya untuk transfer
    category_id   BIGINT,
    kind          TEXT NOT NULL CHECK (kind IN ('income', 'expense', 'transfer')),
    amount        BIGINT NOT NULL CHECK (amount > 0),
    note          TEXT,
    occurred_on   DATE NOT NULL DEFAULT CURRENT_DATE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    -- dompet harus milik pengguna yang sama
    FOREIGN KEY (wallet_id, user_id)    REFERENCES wallets (id, user_id) ON DELETE CASCADE,
    FOREIGN KEY (to_wallet_id, user_id) REFERENCES wallets (id, user_id) ON DELETE CASCADE,
    -- jenis kategori harus sama dengan jenis transaksi
    FOREIGN KEY (category_id, kind)     REFERENCES categories (id, kind),
    CHECK (
        (kind = 'transfer' AND to_wallet_id IS NOT NULL AND to_wallet_id <> wallet_id AND category_id IS NULL) OR
        (kind <> 'transfer' AND to_wallet_id IS NULL AND category_id IS NOT NULL)
    )
);

CREATE TABLE budgets (
    id            BIGSERIAL PRIMARY KEY,
    user_id       BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    category_id   BIGINT NOT NULL REFERENCES categories(id) ON DELETE CASCADE,
    month         DATE NOT NULL CHECK (EXTRACT(DAY FROM month) = 1),
    limit_amount  BIGINT NOT NULL CHECK (limit_amount > 0),
    UNIQUE (user_id, category_id, month)
);

CREATE TABLE saving_goals (
    id             BIGSERIAL PRIMARY KEY,
    user_id        BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name           TEXT NOT NULL,
    target_amount  BIGINT NOT NULL CHECK (target_amount > 0),
    saved_amount   BIGINT NOT NULL DEFAULT 0 CHECK (saved_amount >= 0),
    deadline       DATE
);

CREATE INDEX idx_tx_user_date ON transactions (user_id, occurred_on DESC);

CREATE VIEW v_wallet_balances AS
SELECT w.id AS wallet_id, w.user_id, w.name,
       w.initial_balance + COALESCE(SUM(
           CASE WHEN t.kind = 'income' THEN t.amount
                WHEN t.kind = 'transfer' AND t.to_wallet_id = w.id THEN t.amount
                ELSE -t.amount END), 0) AS balance
FROM wallets w
LEFT JOIN transactions t ON t.wallet_id = w.id OR t.to_wallet_id = w.id
GROUP BY w.id;
