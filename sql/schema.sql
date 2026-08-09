CREATE TABLE users (
    user_id       TEXT PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    display_name  TEXT NOT NULL,
    ctime         TIMESTAMPTZ NOT NULL DEFAULT now(),
    mtime         TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT users_user_id_valid CHECK (
        length(user_id) > 0
        AND position('/' IN user_id) = 0
    )
);

CREATE TABLE teams (
    team_id    BIGSERIAL PRIMARY KEY,
    team_name  TEXT NOT NULL UNIQUE,
    ctime      TIMESTAMPTZ NOT NULL DEFAULT now(),
    mtime      TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT teams_name_valid CHECK (length(team_name) > 0)
);

CREATE TABLE drives (
    drive_id    BIGSERIAL PRIMARY KEY,
    team_id     BIGINT NOT NULL UNIQUE
        REFERENCES teams(team_id) ON DELETE CASCADE,
    drive_name  TEXT NOT NULL,
    ctime       TIMESTAMPTZ NOT NULL DEFAULT now(),
    mtime       TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT drives_name_valid CHECK (length(drive_name) > 0)
);

CREATE TABLE team_members (
    user_id  TEXT NOT NULL
        REFERENCES users(user_id) ON DELETE CASCADE,
    team_id  BIGINT NOT NULL
        REFERENCES teams(team_id) ON DELETE CASCADE,
    ctime    TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, team_id)
);

-- For this phase these are service credentials minted administratively.
-- There is deliberately no login/password-reset/user-management HTTP API.
--
-- The CLI mints a cryptographically random high-entropy secret and displays
-- the plaintext exactly once. Store only a hash/digest appropriate for a
-- high-entropy machine-generated credential.
CREATE TABLE app_passwords (
    app_password_id  BIGSERIAL PRIMARY KEY,
    user_id          TEXT NOT NULL
        REFERENCES users(user_id) ON DELETE CASCADE,
    name             TEXT NOT NULL DEFAULT 'app',
    secret_digest    TEXT NOT NULL UNIQUE,
    ctime            TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_used_at     TIMESTAMPTZ,
    CONSTRAINT app_passwords_name_valid CHECK (length(name) > 0)
);

-- Physical bytes are deliberately separated from logical file/security
-- identity. Do not collapse storage-provider identity into Drive identity.
CREATE TABLE blobs (
    blob_id             BIGSERIAL PRIMARY KEY,
    sha256              TEXT NOT NULL,
    size                BIGINT NOT NULL CHECK (size >= 0),
    storage_key         TEXT NOT NULL,
    storage_version_id   TEXT,
    ctime               TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT blobs_sha256_format CHECK (
        sha256 ~ '^[0-9a-f]{64}$'
    )
);

CREATE INDEX blobs_sha256_idx ON blobs (sha256);

-- One logical file is in exactly one security location:
--
--   owner_user_id XOR drive_id
--
-- File identity is independent of its location and of its current blob.
CREATE TABLE files (
    file_id         BIGSERIAL PRIMARY KEY,
    owner_user_id   TEXT
        REFERENCES users(user_id) ON DELETE CASCADE,
    drive_id        BIGINT
        REFERENCES drives(drive_id) ON DELETE CASCADE,
    name            TEXT NOT NULL,
    blob_id         BIGINT NOT NULL
        REFERENCES blobs(blob_id),
    mime_type       TEXT,
    etag            TEXT NOT NULL,
    revision        BIGINT NOT NULL DEFAULT 1 CHECK (revision > 0),
    ctime           TIMESTAMPTZ NOT NULL DEFAULT now(),
    mtime           TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT files_exactly_one_location CHECK (
        (owner_user_id IS NOT NULL AND drive_id IS NULL)
        OR
        (owner_user_id IS NULL AND drive_id IS NOT NULL)
    ),
    CONSTRAINT files_flat_name CHECK (
        length(name) > 0
        AND position('/' IN name) = 0
    )
);

CREATE UNIQUE INDEX files_personal_name_uq
    ON files (owner_user_id, name)
    WHERE owner_user_id IS NOT NULL;

CREATE UNIQUE INDEX files_drive_name_uq
    ON files (drive_id, name)
    WHERE drive_id IS NOT NULL;

CREATE INDEX files_blob_id_idx ON files (blob_id);
CREATE INDEX files_drive_id_idx ON files (drive_id)
    WHERE drive_id IS NOT NULL;
CREATE INDEX files_owner_user_id_idx ON files (owner_user_id)
    WHERE owner_user_id IS NOT NULL;

-- Append-only audit of meaningful logical mutations.
--
-- file_id is intentionally NOT a foreign key because audit rows must survive
-- deletion of the current logical file record.
CREATE TABLE file_events (
    event_id             BIGSERIAL PRIMARY KEY,
    file_id              BIGINT NOT NULL,
    actor_user_id        TEXT NOT NULL
        REFERENCES users(user_id),
    event_type           TEXT NOT NULL
        CHECK (event_type IN (
            'created',
            'content_replaced',
            'moved_to_drive',
            'deleted'
        )),
    from_owner_user_id   TEXT,
    from_drive_id        BIGINT,
    to_owner_user_id     TEXT,
    to_drive_id          BIGINT,
    file_name            TEXT NOT NULL,
    revision             BIGINT NOT NULL,
    ctime                TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX file_events_file_id_idx
    ON file_events (file_id, event_id);
CREATE INDEX file_events_actor_idx
    ON file_events (actor_user_id, event_id);
