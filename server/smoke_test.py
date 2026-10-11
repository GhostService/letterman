#!/usr/bin/env python3
"""End-to-end check of the PocketBase rules and hooks.

Starts a throwaway PocketBase with this folder's migrations and hooks, then acts as
volunteers, operators and an admin to prove every security rule holds.

Usage (from the server/ folder, after downloading the pocketbase binary here):
    python3 smoke_test.py
"""
import json
import os
import secrets
import sqlite3
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
PORT = 8099
BASE = f"http://127.0.0.1:{PORT}"
# 1x1 transparent PNG, base64.
PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="

failures = []


def check(name, cond, detail=""):
    print(("PASS " if cond else "FAIL ") + name + ("" if cond else f"  -> {detail}"))
    if not cond:
        failures.append(name)


def call(method, path, token=None, body=None):
    # The real rate limits are on; wait them out instead of loosening them for the test.
    for _ in range(30):
        status, result = _call(method, path, token, body)
        if status != 429:
            return status, result
        time.sleep(1)
    return status, result


def _call(method, path, token=None, body=None):
    req = urllib.request.Request(BASE + path, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", token)
    data = json.dumps(body).encode() if body is not None else None
    try:
        with urllib.request.urlopen(req, data, timeout=10) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else {})
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, (json.loads(raw) if raw else {})


def iso(dt):
    return dt.strftime("%Y-%m-%d %H:%M:%S.000Z")


def main():
    binary = os.path.join(HERE, "pocketbase")
    if not os.path.exists(binary):
        sys.exit("Download the pocketbase binary into server/ first (see FIRST_SETUP.md).")

    data_dir = tempfile.mkdtemp(prefix="pb_smoke_")
    env = dict(os.environ, PB_FIELD_KEY=secrets.token_urlsafe(24)[:32])
    common = ["--dir", data_dir, "--migrationsDir", os.path.join(HERE, "pb_migrations"),
              "--hooksDir", os.path.join(HERE, "pb_hooks"), "--encryptionEnv", "PB_FIELD_KEY"]
    admin_email, admin_pw = "admin@smoke.test", secrets.token_urlsafe(16)
    subprocess.run([binary, "superuser", "upsert", admin_email, admin_pw, *common],
                   env=env, check=True, capture_output=True)
    server = subprocess.Popen([binary, "serve", "--http", f"127.0.0.1:{PORT}", *common],
                              env=env, stdout=subprocess.DEVNULL, stderr=subprocess.STDOUT)
    try:
        for _ in range(50):
            try:
                if call("GET", "/api/health")[0] == 200:
                    break
            except OSError:
                pass
            time.sleep(0.1)
        run(admin_email, admin_pw, data_dir)
    finally:
        server.terminate()
        server.wait()

    print()
    if failures:
        print(f"{len(failures)} check(s) failed: {', '.join(failures)}")
        sys.exit(1)
    print("All checks passed.")


def run(admin_email, admin_pw, data_dir):
    _, r = call("POST", "/api/collections/_superusers/auth-with-password",
                body={"identity": admin_email, "password": admin_pw})
    admin = r["token"]
    pw = "correct-horse-battery"

    def signup(email, name, **extra):
        s, r = call("POST", "/api/collections/users/records",
                    body={"email": email, "password": pw, "passwordConfirm": pw, "name": name, **extra})
        assert s == 200, (s, r)
        return r["id"]

    def login(email):
        s, r = call("POST", "/api/collections/users/auth-with-password",
                    body={"identity": email, "password": pw})
        assert s == 200, (s, r)
        return r["token"]

    def admin_set(uid, **fields):
        s, r = call("PATCH", f"/api/collections/users/records/{uid}", admin, fields)
        assert s == 200, (s, r)

    # --- accounts ---
    s, _ = call("POST", "/api/collections/users/records",
                body={"email": "sneaky@t.test", "password": pw, "passwordConfirm": pw,
                      "name": "Sneaky", "role": "operator"})
    check("signup cannot set role", 400 <= s < 500, s)

    v1 = signup("v1@t.test", "Vol One", phone="555-0101", school="Lincoln High", grade="11")
    unverified = signup("u@t.test", "Not Verified")
    o1 = signup("o1@t.test", "Op One", operator_requested=True, org_name="Food Bank")
    o2 = signup("o2@t.test", "Op Two", operator_requested=True, org_name="Library")
    for uid in (v1, o1, o2):
        admin_set(uid, verified=True)
    for uid in (o1, o2):
        admin_set(uid, role="operator")
    tv1, tu, to1, to2 = login("v1@t.test"), login("u@t.test"), login("o1@t.test"), login("o2@t.test")

    s, _ = call("PATCH", f"/api/collections/users/records/{v1}", tv1, {"role": "operator"})
    check("user cannot make themselves operator", 400 <= s < 500, s)
    call("PATCH", f"/api/collections/users/records/{unverified}", tu, {"verified": True})
    _, r = call("GET", f"/api/collections/users/records/{unverified}", admin)
    check("user cannot verify themselves", r.get("verified") is False, r)
    _, r = call("GET", f"/api/collections/users/records/{v1}", tv1)
    check("own profile reads back decrypted", r.get("name") == "Vol One" and r.get("phone") == "555-0101", r)
    s, r = call("GET", f"/api/collections/users/records/{o1}", tv1)
    check("users cannot read other users", s == 404, s)

    # --- unverified users are locked out ---
    s, r = call("GET", "/api/collections/opportunities/records", tu)
    check("unverified sees no opportunities", s in (200, 403) and not r.get("items"), r)
    s, _ = call("POST", "/api/collections/hour_logs/records", tu,
                {"owner": unverified, "started_at": iso(datetime.now(timezone.utc)), "hours": 1, "place_name": "X"})
    check("unverified cannot log hours", 400 <= s < 500, s)

    # --- opportunities ---
    tomorrow = iso(datetime.now(timezone.utc) + timedelta(days=1))
    opp_body = {"title": "Pantry shift", "org_name": "Food Bank", "address": "88 Mill St",
                "starts_at": tomorrow, "duration_hours": 3, "spots_needed": 2}
    s, _ = call("POST", "/api/collections/opportunities/records", tv1, {**opp_body, "operator": v1})
    check("volunteer cannot post opportunity", 400 <= s < 500, s)
    s, r = call("POST", "/api/collections/opportunities/records", to1, {**opp_body, "operator": o1})
    check("operator posts opportunity", s == 200, r)
    opp = r["id"]
    check("new opportunity has 0 filled", r.get("spots_filled") == 0, r)
    s, _ = call("PATCH", f"/api/collections/opportunities/records/{opp}", to2, {"title": "Hijacked"})
    check("operator cannot edit another's listing", s == 404, s)
    s, _ = call("PATCH", f"/api/collections/opportunities/records/{opp}", to1, {"operator": o2})
    check("operator cannot give listing away", 400 <= s < 500, s)
    s, r = call("PATCH", f"/api/collections/opportunities/records/{opp}", to1, {"lat": 39.7817, "lng": -89.6501})
    check("listing stores map coordinates", s == 200 and r.get("lat") == 39.7817 and r.get("lng") == -89.6501, r)
    s, _ = call("PATCH", f"/api/collections/opportunities/records/{opp}", to1, {"lat": 91})
    check("impossible latitude rejected", 400 <= s < 500, s)

    # --- signups ---
    s, r = call("POST", "/api/collections/signups/records", tv1, {"opportunity": opp, "volunteer": v1})
    check("volunteer signs up", s == 200, r)
    check("signup response shows decrypted snapshot", r.get("phone") == "555-0101" and r.get("email") == "v1@t.test", r)
    signup_id = r.get("id")
    s, _ = call("POST", "/api/collections/signups/records", tv1, {"opportunity": opp, "volunteer": v1})
    check("duplicate signup rejected", 400 <= s < 500, s)
    s, _ = call("POST", "/api/collections/signups/records", tv1, {"opportunity": opp, "volunteer": o1})
    check("cannot sign up someone else", 400 <= s < 500, s)
    s, _ = call("POST", "/api/collections/signups/records", to1, {"opportunity": opp, "volunteer": o1})
    check("operator cannot sign up as volunteer", 400 <= s < 500, s)
    _, r = call("GET", f"/api/collections/opportunities/records/{opp}", tv1)
    check("spots_filled counts signups", r.get("spots_filled") == 1, r)

    _, r = call("GET", f"/api/collections/signups/records?filter=(opportunity='{opp}')", to1)
    items = r.get("items", [])
    check("operator sees attendee contact info",
          len(items) == 1 and items[0]["name"] == "Vol One" and items[0]["school"] == "Lincoln High", r)
    _, r = call("GET", f"/api/collections/signups/records?filter=(opportunity='{opp}')", to2)
    check("other operator sees no attendees", r.get("items") == [], r)

    s, r = call("PATCH", f"/api/collections/opportunities/records/{opp}", to1, {"spots_needed": 1})
    check("spots_needed can drop to the filled count", s == 200, r)
    s, _ = call("PATCH", f"/api/collections/opportunities/records/{opp}", to1, {"spots_needed": 0})
    check("spots_needed cannot drop below filled count", 400 <= s < 500, s)

    # Race: 8 volunteers grab 3 spots at the same moment.
    s, r = call("POST", "/api/collections/opportunities/records", to1,
                {**opp_body, "operator": o1, "spots_needed": 3, "title": "Race"})
    race = r["id"]
    racers = []
    for i in range(8):
        uid = signup(f"r{i}@t.test", f"Racer {i}")
        admin_set(uid, verified=True)
        racers.append((uid, login(f"r{i}@t.test")))
    with ThreadPoolExecutor(8) as pool:
        codes = list(pool.map(lambda ut: call("POST", "/api/collections/signups/records", ut[1],
                                              {"opportunity": race, "volunteer": ut[0]})[0], racers))
    check("no overbooking under concurrent signups", codes.count(200) == 3, codes)
    _, r = call("GET", f"/api/collections/opportunities/records/{race}", tv1)
    check("race listing shows 3 filled", r.get("spots_filled") == 3, r)

    s, r = call("POST", "/api/collections/opportunities/records", to1,
                {**opp_body, "operator": o1, "title": "Past",
                 "starts_at": iso(datetime.now(timezone.utc) - timedelta(days=1))})
    s, _ = call("POST", "/api/collections/signups/records", tv1, {"opportunity": r["id"], "volunteer": v1})
    check("cannot sign up for past opportunity", 400 <= s < 500, s)

    # --- hour logs ---
    log = {"owner": v1, "started_at": iso(datetime.now(timezone.utc)), "hours": 3,
           "place_name": "Riverside Food Bank", "address": "88 Mill St", "comments": "Sorted cans"}
    s, _ = call("POST", "/api/collections/hour_logs/records", tv1, {**log, "signature": PNG})
    check("signature without supervisor name rejected", 400 <= s < 500, s)
    s, _ = call("POST", "/api/collections/hour_logs/records", tv1,
                {**log, "signature": "bm90IGEgcG5n", "signer_name": "D. Alvarez"})
    check("non-PNG signature rejected", 400 <= s < 500, s)
    s, r = call("POST", "/api/collections/hour_logs/records", tv1,
                {**log, "signature": PNG, "signer_name": "D. Alvarez", "signed_at": "2020-01-01 00:00:00.000Z"})
    check("signed log created", s == 200 and r.get("signature") == PNG and r.get("place_name") == "Riverside Food Bank", r)
    check("server sets signed_at (no backdating)", r.get("signed_at", "").startswith(str(datetime.now(timezone.utc).year)), r)
    signed_log = r["id"]
    s, _ = call("PATCH", f"/api/collections/hour_logs/records/{signed_log}", tv1, {"hours": 10})
    check("signed log is locked", s == 404, s)

    # The app picks the id of a new log so a retried upload can't create a duplicate.
    s, r = call("POST", "/api/collections/hour_logs/records", tv1, {**log, "id": "retrytest000001"})
    check("client can choose a new log's id", s == 200 and r.get("id") == "retrytest000001", r)
    s, _ = call("POST", "/api/collections/hour_logs/records", tv1, {**log, "id": "retrytest000001"})
    check("retrying the same id is rejected (no duplicate)", s == 400, s)

    s, r = call("POST", "/api/collections/hour_logs/records", tv1, log)
    draft = r["id"]
    s, _ = call("PATCH", f"/api/collections/hour_logs/records/{draft}", tv1, {"hours": 4})
    check("unsigned log can be edited", s == 200, s)
    s, r = call("PATCH", f"/api/collections/hour_logs/records/{draft}", tv1, {"signature": PNG, "signer_name": "J. Park"})
    check("unsigned log can be signed later", s == 200 and r.get("signed_at"), r)
    s, _ = call("PATCH", f"/api/collections/hour_logs/records/{draft}", tv1, {"hours": 9})
    check("log is locked after signing", s == 404, s)

    s, _ = call("GET", f"/api/collections/hour_logs/records/{signed_log}", login("r0@t.test"))
    check("other users cannot read a log", s == 404, s)
    s, _ = call("GET", f"/api/collections/hour_logs/records/{signed_log}", to1)
    check("operators cannot read volunteer logs", s == 404, s)

    # --- changes and cancellations (attendees are emailed; a mail problem must never block the operator) ---
    s, r = call("POST", "/api/collections/opportunities/records", to1, {**opp_body, "operator": o1, "title": "Will cancel"})
    cancel = r["id"]
    call("POST", "/api/collections/signups/records", tv1, {"opportunity": cancel, "volunteer": v1})
    s, r = call("POST", "/api/collections/hour_logs/records", tv1, {**log, "opportunity": cancel})
    check("log can point at the listing it came from", s == 200 and r.get("opportunity") == cancel, r)
    linked = r["id"]
    s, r = call("PATCH", f"/api/collections/opportunities/records/{cancel}", to1,
                {"starts_at": iso(datetime.now(timezone.utc) + timedelta(days=2))})
    check("moving a listing with attendees still saves", s == 200, r)
    s, _ = call("DELETE", f"/api/collections/opportunities/records/{cancel}", to1)
    check("cancelling a listing with attendees still works", s == 204, s)
    _, r = call("GET", f"/api/collections/hour_logs/records/{linked}", tv1)
    check("cancelling a listing keeps logs and clears their link", r.get("id") == linked and r.get("opportunity") == "", r)

    s, r = call("PATCH", f"/api/collections/users/records/{v1}", tv1, {"phone": "555-0199", "hours_goal": 40})
    check("profile update reads back decrypted", s == 200 and r.get("phone") == "555-0199" and r.get("name") == "Vol One", r)

    # --- encryption at rest (read the SQLite file directly) ---
    db = sqlite3.connect(os.path.join(data_dir, "data.db"))
    name, phone = db.execute("SELECT name, phone FROM users WHERE id = ?", (v1,)).fetchone()
    check("user PII encrypted on disk (after update too)", name.startswith("enc:") and phone.startswith("enc:"), (name, phone))
    sig, place = db.execute("SELECT signature, place_name FROM hour_logs WHERE id = ?", (signed_log,)).fetchone()
    check("signature + place encrypted on disk", sig.startswith("enc:") and place.startswith("enc:"), (sig[:20], place))
    snap = db.execute("SELECT email, phone FROM signups WHERE id = ?", (signup_id,)).fetchone()
    check("signup snapshot encrypted on disk", all(v.startswith("enc:") for v in snap), snap)
    db.close()

    # --- account deletion cascades and frees the spot ---
    s, _ = call("DELETE", f"/api/collections/users/records/{v1}", tv1)
    check("volunteer can delete their account", s == 204, s)
    _, r = call("GET", f"/api/collections/opportunities/records/{opp}", to1)
    check("deleting account frees the spot", r.get("spots_filled") == 0, r)
    _, r = call("GET", "/api/collections/hour_logs/records", admin)
    check("deleting account removes their logs", r.get("totalItems") == 0, r)


if __name__ == "__main__":
    main()
