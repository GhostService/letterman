#!/usr/bin/env python3
"""Fills a LOCAL dev server (./dev.sh) with demo accounts and data. Never run this against the real server.

Demo logins (local only):
    volunteer@example.test / devpassword123
    operator@example.test  / devpassword123
    dashboard admin: admin@example.test / devpassword123  (http://127.0.0.1:8090/_/)
"""
import base64
import os
from datetime import datetime, timedelta, timezone

import smoke_test
from smoke_test import call, iso

smoke_test.BASE = "http://127.0.0.1:8090"

HERE = os.path.dirname(os.path.abspath(__file__))
PASSWORD = "devpassword123"


def main():
    if call("GET", "/api/health")[0] != 200:
        raise SystemExit("Start the dev server first: ./dev.sh")

    _, r = call("POST", "/api/collections/_superusers/auth-with-password",
                body={"identity": "admin@example.test", "password": PASSWORD})
    admin = r["token"]

    def user(email, **fields):
        s, r = call("POST", "/api/collections/users/records", admin,
                    {"email": email, "password": PASSWORD, "passwordConfirm": PASSWORD, "verified": True, **fields})
        if s != 200:
            raise SystemExit(f"{email}: {r.get('message')} (already seeded? delete server/pb_data to start over)")
        _, auth = call("POST", "/api/collections/users/auth-with-password", body={"identity": email, "password": PASSWORD})
        return r["id"], auth["token"]

    vol, vol_t = user("volunteer@example.test", name="Maya Chen", phone="(555) 201-4432",
                      school="Lincoln High", grade="11", hours_goal=40)
    op, op_t = user("operator@example.test", name="Dana Whitfield", role="operator",
                    operator_requested=True, org_name="Riverside Food Bank")
    others = [user(f"student{i}@example.test", name=n, school=s, grade=g, phone=p)
              for i, (n, s, g, p) in enumerate([
                  ("Jordan Reyes", "Lincoln High", "12", ""),
                  ("Aisha Patel", "Westbrook Academy", "10", "(555) 877-0912"),
                  ("Theo Nguyen", "Lincoln High", "9", "(555) 340-1187"),
                  ("Sam Ortiz", "Lincoln High", "11", "(555) 610-2290"),
              ])]

    now = datetime.now(timezone.utc).replace(minute=0, second=0, microsecond=0)

    def at(days, hour):
        local = (datetime.now().astimezone() + timedelta(days=days)).replace(hour=hour, minute=0, second=0, microsecond=0)
        return iso(local.astimezone(timezone.utc))

    opps = {}
    for title, org, addr, days, hour, dur, spots, desc in [
        ("Saturday pantry shift", "Riverside Food Bank", "88 Mill St", 6, 9, 3, 8, "Sort donations and pack grocery boxes for families."),
        ("Mill Creek trail cleanup", "Riverside Food Bank", "Trailhead lot B, Mill Creek Park", 7, 8, 4, 6, "Pick up litter along the creek trail. Gloves and bags provided."),
        ("Reading buddies", "Riverside Food Bank", "200 Oak Hill Ave", 9, 15, 1.5, 6, "Read with kids in grades 1 to 3 at the library."),
        ("Holiday food drive setup", "Riverside Food Bank", "88 Mill St", 20, 10, 2, 12, "Set up collection bins and signs before the drive starts."),
    ]:
        _, r = call("POST", "/api/collections/opportunities/records", op_t,
                    {"operator": op, "title": title, "org_name": org, "address": addr, "starts_at": at(days, hour),
                     "duration_hours": dur, "spots_needed": spots, "description": desc})
        opps[title] = r["id"]

    for uid, tok in [(vol, vol_t), *others]:
        call("POST", "/api/collections/signups/records", tok, {"opportunity": opps["Saturday pantry shift"], "volunteer": uid})
    for uid, tok in others[:3]:
        call("POST", "/api/collections/signups/records", tok, {"opportunity": opps["Mill Creek trail cleanup"], "volunteer": uid})

    sig = base64.b64encode(open(os.path.join(HERE, "dev_signature.png"), "rb").read()).decode()
    for place, addr, days, hour, hrs, signer, comments in [
        ("Riverside Food Bank", "88 Mill St", -7, 9, 3, "D. Alvarez", "Sorted canned goods and packed 40 boxes."),
        ("Habitat for Humanity", "1200 Elm St", -14, 8, 6, "R. Okafor", "Framing crew on the new house."),
        ("Oak Hill Library", "200 Oak Hill Ave", -20, 13, 2.5, "J. Park", "Set up the used book sale."),
        ("Lakeview Animal Shelter", "412 Shoreline Rd", -27, 10, 21, "K. Brooks", "Summer kennel program, three weekends."),
        ("Lakeview Animal Shelter", "412 Shoreline Rd", -1, 10, 4, None, "Cleaned kennels and walked dogs."),
    ]:
        body = {"owner": vol, "place_name": place, "address": addr, "started_at": at(days, hour), "hours": hrs, "comments": comments}
        if signer:
            body |= {"signature": sig, "signer_name": signer}
        call("POST", "/api/collections/hour_logs/records", vol_t, body)

    call("POST", "/api/collections/calendar_events/records", vol_t,
         {"owner": vol, "title": "Drop off coat drive boxes", "starts_at": at(6, 14), "duration_hours": 1,
          "location": "St. Mark's Community Center"})
    print("Seeded. Sign in as volunteer@example.test or operator@example.test (password in this file).")


if __name__ == "__main__":
    main()
