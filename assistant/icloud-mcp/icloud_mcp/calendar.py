"""iCloud Calendar over CalDAV (caldav.icloud.com, same app-specific password)."""
from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

from .mail import _creds

CALDAV_URL = os.environ.get("ICLOUD_CALDAV_URL", "https://caldav.icloud.com")


def _client():
    import caldav  # imported lazily so mail works even if caldav is missing
    user, pw = _creds()
    return caldav.DAVClient(url=CALDAV_URL, username=user, password=pw)


def _calendars():
    return _client().principal().calendars()


def _parse(s: str) -> datetime:
    dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)


def list_calendars() -> list[str]:
    return [c.name for c in _calendars()]


def events(days_ahead: int = 7, days_back: int = 0, calendar: str | None = None) -> list[dict]:
    start = datetime.now(timezone.utc) - timedelta(days=days_back)
    end = datetime.now(timezone.utc) + timedelta(days=days_ahead)
    out = []
    for cal in _calendars():
        if calendar and cal.name != calendar:
            continue
        for ev in cal.search(start=start, end=end, event=True, expand=True):
            comp = ev.icalendar_component
            def g(k):
                v = comp.get(k)
                return getattr(v, "dt", v)
            out.append({
                "calendar": cal.name,
                "title": str(comp.get("SUMMARY", "")),
                "start": str(g("DTSTART")),
                "end": str(g("DTEND") or ""),
                "location": str(comp.get("LOCATION", "") or ""),
                "notes": str(comp.get("DESCRIPTION", "") or "")[:500],
                "uid": str(comp.get("UID", "")),
            })
    out.sort(key=lambda e: e["start"])
    return out


def create_event(title: str, start: str, end: str, calendar: str | None = None,
                 location: str = "", notes: str = "") -> dict:
    cals = _calendars()
    cal = next((c for c in cals if c.name == calendar), None) if calendar else None
    cal = cal or cals[0]
    kw = {"dtstart": _parse(start), "dtend": _parse(end), "summary": title}
    if location:
        kw["location"] = location
    if notes:
        kw["description"] = notes
    cal.save_event(**kw)
    return {"created": title, "calendar": cal.name, "start": start, "end": end}
