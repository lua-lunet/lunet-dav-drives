-- Fixture users for the NCe31 compat specs (issue #2, specs/loginflow and
-- specs/ocs). The plaintext fixture password is `fixture-password`, kept in
-- e2e/run-e2e.sh as FIXTURE_PASSWORD; the digests below are Argon2id encoded,
-- generated per .tmp/item07-argon2id.lua (random salt per run — any valid
-- encoding of the fixture password works).
INSERT INTO users (user_id, email, display_name, password_digest) VALUES ('u1', 'u1@example.test', 'Fixture U1', '$argon2id$v=19$m=65536,t=2,p=1$GGCXNkwbDUIuoWupopiY9g$20WOjO9co4Mv9p8Zx5ElzRKuNvkNxR54SbtGOxNvKG8'), ('u2', 'u2@example.test', 'Fixture U2', '$argon2id$v=19$m=65536,t=2,p=1$6HRkdsAA0aY7QB55ANE52g$Op2+AviYcrlgL5Hg7MImsOplzjmDPbIIScx78fTr9FY');
