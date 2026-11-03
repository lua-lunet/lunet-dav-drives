#!/usr/bin/env python3
"""One-shot bootstrap for the Garage e2e node (single node, layout, bucket, key).

Idempotent: safe to re-run. The access key is REUSED when its secret is
already on file in /creds/s3.env (stable credentials across stack restarts);
it is recreated fresh only when the secret is unknown. Credentials are
written to /creds/s3.env for run-e2e.sh and printed.

Env: ADMIN_URL (default http://garage:3903), ADMIN_TOKEN, BUCKET, KEY_NAME,
CREDS_FILE (default /creds/s3.env).
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

ADMIN = os.environ.get("ADMIN_URL", "http://garage:3903")
TOKEN = os.environ.get("ADMIN_TOKEN", "e2e-admin-token-not-secret")
BUCKET = os.environ.get("BUCKET", "lunet-dav-drives")
KEY_NAME = os.environ.get("KEY_NAME", "lunet-e2e")
CREDS_FILE = os.environ.get("CREDS_FILE", "/creds/s3.env")


def call(method, path, body=None, ok=(200,)):
    req = urllib.request.Request(
        ADMIN + path,
        method=method,
        data=json.dumps(body).encode() if body is not None else None,
        headers={"Authorization": f"Bearer {TOKEN}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            data = r.read()
            code = r.status
    except urllib.error.HTTPError as e:
        data = e.read()
        code = e.code
    if code not in ok:
        raise RuntimeError(f"{method} {path} -> {code}: {data[:300].decode(errors='replace')}")
    return json.loads(data) if data else {}


def wait_reachable(seconds=60):
    """Wait until the admin API answers AT ALL. /health is 503 on a fresh
    volume (no layout yet) — that is still 'reachable' for our purposes."""
    deadline = time.time() + seconds
    while time.time() < deadline:
        req = urllib.request.Request(ADMIN + "/health", method="GET")
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                if r.status == 200:
                    return
        except urllib.error.HTTPError:
            return  # admin answered (e.g. 503 pre-layout) — good enough
        except Exception:
            time.sleep(1)
    raise RuntimeError("garage admin never became reachable")


def ensure_layout():
    status = call("GET", "/v2/GetClusterStatus")
    node = next(n["id"] for n in status["nodes"] if n.get("isUp"))
    layout = call("GET", "/v2/GetClusterLayout")
    if any(r["id"] == node and r.get("capacity") for r in layout["roles"]):
        print("layout: node already assigned")
        return
    call("POST", "/v2/UpdateClusterLayout", {
        "roles": [{"id": node, "zone": "dc1", "capacity": 1073741824, "tags": ["e2e"]}],
    })
    call("POST", "/v2/ApplyClusterLayout", {"version": layout["version"] + 1})
    print("layout: assigned node", node[:8])


def ensure_bucket():
    try:
        call("GET", f"/v2/GetBucketInfo?globalAlias={BUCKET}")
        print("bucket: exists")
        return
    except RuntimeError:
        pass
    call("POST", "/v2/CreateBucket", {"globalAlias": BUCKET})
    print("bucket: created", BUCKET)


def ensure_key():
    """Reuse the named key when its secret is already known (creds file
    matches a live key); delete+recreate only when the secret is unknown.
    Without this, every stack start invalidates credentials read by
    run-e2e.sh. NOTE: keys created via the admin ImportKey path are not
    reliably visible to the S3 API on a single node (v2.0.0) — CreateKey
    (garage-generated) is, which is why rotation (not import) is the
    fallback."""
    existing_ak = None
    existing_sk = None
    if os.path.exists(CREDS_FILE):
        with open(CREDS_FILE) as f:
            for line in f:
                if line.startswith("S3_ACCESS_KEY_ID="):
                    existing_ak = line.split("=", 1)[1].strip()
                elif line.startswith("S3_SECRET_ACCESS_KEY="):
                    existing_sk = line.split("=", 1)[1].strip()

    keys = call("GET", "/v2/ListKeys")
    for k in keys:
        if k.get("name") == KEY_NAME:
            key_id = k.get("accessKeyId") or k.get("id")
            if existing_ak and existing_sk and existing_ak == key_id:
                ak, sk = existing_ak, existing_sk
                print("key: reused", ak)
                break
            call("POST", f"/v2/DeleteKey?id={key_id}")
    else:
        created = call("POST", "/v2/CreateKey", {"name": KEY_NAME})
        ak, sk = created["accessKeyId"], created["secretAccessKey"]
        print("key: fresh", ak)

    bucket = call("GET", f"/v2/GetBucketInfo?globalAlias={BUCKET}")
    call("POST", "/v2/AllowBucketKey", {
        "bucketId": bucket["id"], "accessKeyId": ak,
        "permissions": {"owner": False, "read": True, "write": True},
    })

    os.makedirs(os.path.dirname(CREDS_FILE), exist_ok=True)
    with open(CREDS_FILE, "w") as f:
        f.write(f"S3_ACCESS_KEY_ID={ak}\nS3_SECRET_ACCESS_KEY={sk}\n")
    os.chmod(CREDS_FILE, 0o600)


def main():
    wait_reachable()
    ensure_layout()
    ensure_bucket()
    ensure_key()
    print("BOOTSTRAP OK")


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print("BOOTSTRAP FAILED:", e, file=sys.stderr)
        sys.exit(1)
