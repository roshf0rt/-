"""Что изменилось в расписании: пара отменена, добавлена, перенесена или сменила кабинет."""
import hashlib
import json
from dataclasses import dataclass
from datetime import datetime, timedelta

from urfu import TZ, Pair

# Сколько дней вперёд сравниваем. Окно расписания скользит: дальний край каждый день
# «добавляет» пары, и это не изменение.
HORIZON_DAYS = 13
# Отменённую и добавленную пару с тем же названием считаем переносом, если они не дальше друг от друга.
MOVE_WINDOW = timedelta(days=7)


@dataclass(frozen=True)
class Change:
    kind: str  # cancelled | added | changed
    pair: Pair
    previous: Pair | None = None


def signature(pairs: list[Pair]) -> str:
    """Отпечаток расписания: одинаковый набор пар даёт одинаковый отпечаток."""
    rows = sorted(f"{p.id}|{p.start.isoformat()}|{p.end.isoformat()}|{p.title}|{p.kind}|{p.room}|{p.subgroup}"
                  for p in pairs)
    return hashlib.sha256("\n".join(rows).encode()).hexdigest()


def pairs_to_json(pairs: list[Pair]) -> str:
    return json.dumps([{"id": p.id, "start": p.start.isoformat(), "end": p.end.isoformat(), "title": p.title,
                        "kind": p.kind, "room": p.room, "subgroup": p.subgroup} for p in pairs],
                      ensure_ascii=False)


def pairs_from_json(text: str) -> list[Pair]:
    return [Pair(datetime.fromisoformat(item["start"]), datetime.fromisoformat(item["end"]), item["title"],
                 item["kind"], item["room"], item["subgroup"], item["id"]) for item in json.loads(text)]


def is_plausible(old: list[Pair], new: list[Pair], now: datetime) -> bool:
    """Похоже ли новое расписание на настоящее, а не на сбой сайта.

    Пустой ответ при непустом старом и резкая потеря пар считаются подозрительными:
    такое изменение принимаем только после повторной проверки.
    """
    before = sum(1 for pair in old if pair.end > now)
    after = sum(1 for pair in new if pair.end > now)
    if before and not after:
        return False
    return before - after <= 3 or after * 10 >= before * 7


def _details(pair: Pair) -> tuple:
    return (pair.start, pair.end, pair.room, pair.title)


def diff(old: list[Pair], new: list[Pair], now: datetime, taken_at: datetime) -> list[Change]:
    """Изменения между старым и новым расписанием, важные для предстоящих пар."""
    horizon = datetime.combine(min(taken_at, now).date(), datetime.min.time(), TZ) + timedelta(days=HORIZON_DAYS)
    old_by_id = {pair.id: pair for pair in old}
    new_by_id = {pair.id: pair for pair in new}

    cancelled = [pair for pid, pair in old_by_id.items()
                 if pid not in new_by_id and pair.end > now and pair.start < horizon]
    added = [pair for pid, pair in new_by_id.items()
             if pid not in old_by_id and pair.start > now and pair.start < horizon]
    changes = []
    for pid, pair in new_by_id.items():
        before = old_by_id.get(pid)
        if before and pair.end > now and pair.start < horizon and _details(before) != _details(pair):
            changes.append(Change("changed", pair, before))

    # Перенос: у новой пары другой идентификатор, но то же название и тип занятия.
    for gone in list(cancelled):
        match = next((pair for pair in added if pair.title == gone.title and pair.kind == gone.kind
                      and abs(pair.start - gone.start) <= MOVE_WINDOW), None)
        if match:
            cancelled.remove(gone)
            added.remove(match)
            changes.append(Change("changed", match, gone))

    changes += [Change("cancelled", pair) for pair in cancelled]
    changes += [Change("added", pair) for pair in added]
    return sorted(changes, key=lambda change: change.pair.start)
