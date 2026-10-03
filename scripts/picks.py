#!/usr/bin/env python3
"""Helper for the /picks Claude Code skill: fetch a day's slate and upload picks.

  picks.py slate <sport_key> [YYYY-MM-DD]   print the day's games + best odds (local time zone)
  picks.py upload <picks.json>              upload picks for the app
  picks.py bets <bets.json>                 send bets read from screenshots to the app's inbox
  picks.py status                           backend health / spend

Backend URL and app token come from ios/Config/Secrets.xcconfig (git-ignored).
"""
import datetime as dt
import json
import pathlib
import sys
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SECRETS = ROOT / "ios" / "Config" / "Secrets.xcconfig"


def config():
    vals = {}
    for line in SECRETS.read_text().splitlines():
        if "=" in line and not line.strip().startswith("//"):
            k, v = line.split("=", 1)
            vals[k.strip()] = v.strip().replace("$()", "")
    return vals["BACKEND_URL"].rstrip("/"), vals["APP_TOKEN"]


def request(path, body=None, timeout=120):
    url, token = config()
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url + path, data=data, headers={"x-app-token": token, "content-type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"Backend error {e.code}: {e.read().decode()[:500]}")


def day_window(date_str=None):
    """Local-time-zone day as UTC ISO strings (matches what the iPhone app requests)."""
    day = dt.date.fromisoformat(date_str) if date_str else dt.date.today()
    start = dt.datetime.combine(day, dt.time()).astimezone()
    end = start + dt.timedelta(days=1)
    iso = lambda t: t.astimezone(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    return day.isoformat(), iso(start), iso(end)


def slate(sport, date_str=None):
    date, start, end = day_window(date_str)
    q = urllib.parse.urlencode({"sports": sport, "from": start, "to": end, "window": "day"})
    games = request(f"/games?{q}")
    now = dt.datetime.now(dt.timezone.utc)
    upcoming = [g for g in games if dt.datetime.fromisoformat(g["startTime"].replace("Z", "+00:00")) > now]
    print(f"# {sport} {date}: {len(upcoming)} upcoming games (window {start} → {end})")
    for g in upcoming:
        t = dt.datetime.fromisoformat(g["startTime"].replace("Z", "+00:00")).astimezone()
        print(f"\nevent_id={g['eventId']}  {g['awayTeam']} @ {g['homeTeam']}  {t:%a %I:%M %p}")
        for mkey, label in (("h2h", "ML"), ("spreads", "Spread"), ("totals", "Total")):
            quotes = g["markets"].get(mkey) or []
            if quotes:
                parts = [f"{q['name']}{'' if q['point'] is None else ' ' + format(q['point'], '+g' if mkey == 'spreads' else 'g')} "
                         f"{q['bestOdds']:+d} ({q['bookmaker']}, fair {q['fairProbability']:.0%})" for q in quotes]
                print(f"  {label}: " + " | ".join(parts))


def upload(path):
    body = json.loads(pathlib.Path(path).read_text())
    date, start, end = day_window(body.get("date"))
    body.update({"date": date, "from": start, "to": end})
    result = request("/picks/upload", body)
    print(f"Saved {result['saved']} picks ({result['dropped']} dropped: not in odds data or no edge at the current price)")
    for line in result["picks"]:
        print("  -", line)


def bets(path):
    body = json.loads(pathlib.Path(path).read_text())
    result = request("/bets/inbox", body)
    print(f"Sent {len(body.get('bets', []))} bets. {result['waiting']} waiting in the app's inbox.")


if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    if cmd == "slate" and len(sys.argv) >= 3:
        slate(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
    elif cmd == "upload" and len(sys.argv) >= 3:
        upload(sys.argv[2])
    elif cmd == "bets" and len(sys.argv) >= 3:
        bets(sys.argv[2])
    elif cmd == "status":
        print(json.dumps(request("/health"), indent=1))
    else:
        sys.exit(__doc__)
