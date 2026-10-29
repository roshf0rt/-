"""Публичное API расписания УрФУ. Недокументированное: может измениться без предупреждения."""
import re
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import aiohttp

TZ = ZoneInfo("Asia/Yekaterinburg")
API = "https://urfu.ru/api/v2/schedule/groups"
# Сайт отвечает 403 на запросы без браузерного User-Agent.
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Accept": "application/json",
}
# Как в приложении: номер подгруппы ищется в тексте вида «1 подгруппа».
SUBGROUP_PATTERNS = [
    re.compile(r"(\d)\s*(?:-?\s*я\s*)?подгрупп", re.IGNORECASE),
    re.compile(r"подгрупп[аы]?\s*(?:№\s*)?(\d)", re.IGNORECASE),
    re.compile(r"(\d)\s*п/г", re.IGNORECASE),
]


@dataclass(frozen=True)
class Group:
    id: str
    name: str


@dataclass(frozen=True)
class Pair:
    start: datetime
    end: datetime
    title: str
    kind: str
    room: str
    subgroup: int | None


async def _get_json(url: str, params: dict | None = None):
    timeout = aiohttp.ClientTimeout(total=20)
    async with aiohttp.ClientSession(headers=HEADERS, timeout=timeout) as session:
        async with session.get(url, params=params) as response:
            response.raise_for_status()
            return await response.json(content_type=None)


async def search_groups(query: str) -> list[Group]:
    data = await _get_json(f"{API}/", {"search": query})
    return [Group(str(item["id"]), item["title"]) for item in data][:8]


async def fetch_pairs(group_id: str, today: date) -> list[Pair]:
    if not group_id.isdigit():
        raise ValueError("group id must be numeric")
    params = {"date_gte": today.isoformat(), "date_lte": (today + timedelta(days=14)).isoformat()}
    data = await _get_json(f"{API}/{group_id}/schedule/", params)
    return parse_pairs(data.get("events", []))


def subgroup_number(text: str) -> int | None:
    for pattern in SUBGROUP_PATTERNS:
        match = pattern.search(text)
        if match and int(match.group(1)) > 0:
            return int(match.group(1))
    return None


def subgroup_of(event: dict) -> int | None:
    for key, value in event.items():
        if "subgroup" not in key.lower():
            continue
        if isinstance(value, int) and 1 <= value <= 9:
            return value
        if isinstance(value, str):
            number = subgroup_number(value) or (int(value) if value.isdigit() else None)
            if number and 1 <= number <= 9:
                return number
    for value in event.values():
        if isinstance(value, str) and (number := subgroup_number(value)):
            return number
    return None


def _time(day: str, value: str) -> datetime | None:
    for fmt in ("%H:%M:%S", "%H:%M"):
        try:
            return datetime.strptime(f"{day} {value}", f"%Y-%m-%d {fmt}").replace(tzinfo=TZ)
        except ValueError:
            pass
    return None


def parse_pairs(events: list[dict]) -> list[Pair]:
    pairs = []
    for event in events:
        day = event.get("date", "")
        start = _time(day, event.get("timeBegin", ""))
        end = _time(day, event.get("timeEnd", ""))
        # Пара без номера в полночь — заглушка расписания, а не настоящая пара.
        placeholder = (event.get("pairNumber") or 0) == 0 and start is not None and start.hour == 0 and start.minute == 0
        if start is None or end is None or placeholder:
            continue
        pairs.append(Pair(start, end, event.get("title", "Без названия"), event.get("loadType", ""),
                          event.get("auditoryTitle") or "", subgroup_of(event)))
    return sorted(pairs, key=lambda pair: pair.start)
