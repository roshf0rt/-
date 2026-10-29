"""Личный Telegram-бот с расписанием группы УрФУ.

Команды: /today, /next, /week. Утром присылает расписание дня и напоминает
за несколько минут до пары. Отвечает только chat id из ALLOWED_CHAT_IDS.
"""
import asyncio
import html
import logging
import os
from dataclasses import dataclass
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo

import aiohttp
from aiogram import Bot, Dispatcher, F
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.filters import Command
from aiogram.types import BotCommand, Message

TZ = ZoneInfo("Asia/Yekaterinburg")
API = "https://urfu.ru/api/v2/schedule/groups"
# Сайт отвечает 403 на запросы без браузерного User-Agent.
HEADERS = {
    "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
                  "(KHTML, like Gecko) Chrome/124.0 Safari/537.36",
    "Accept": "application/json",
}
WEEKDAYS = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]


def premium(emoji_id: str, fallback: str) -> str:
    """Премиум-эмодзи в тексте. Анимация видна при Premium у владельца бота, иначе — обычный эмодзи."""
    return f'<tg-emoji emoji-id="{emoji_id}">{fallback}</tg-emoji>'


E_CALENDAR = premium("5890937706803894250", "📅")
E_CLOCK = premium("5983150113483134607", "⏰")
E_NOW = premium("5773626993010546707", "▶️")
E_NEXT = premium("6037622221625626773", "➡️")
E_DONE = premium("6041731551845159060", "🎉")
E_EMPTY = premium("5983401171501454028", "💤")
E_BOT = premium("6030400221232501136", "🤖")
E_LOCK = premium("6037249452824072506", "🔒")
E_INFO = premium("6028435952299413210", "ℹ️")
E_BELL = premium("6039677157318332604", "🔔")
E_SUN = premium("5938525265838739643", "☀️")
E_WARN = premium("6030563507299160824", "❗️")
E_LIST = premium("5766994197705921104", "🗂")

BOT_TOKEN = os.environ["BOT_TOKEN"]
GROUP_ID = os.environ.get("GROUP_ID", "65979")
ALLOWED = {int(x) for x in os.environ.get("ALLOWED_CHAT_IDS", "").split(",") if x.strip()}
REMIND_MINUTES = int(os.environ.get("REMIND_MINUTES", "10"))
DIGEST_HOUR = int(os.environ.get("DIGEST_HOUR", "8"))

log = logging.getLogger("urfu-bot")
dp = Dispatcher()


@dataclass(frozen=True)
class Pair:
    start: datetime
    end: datetime
    title: str
    kind: str
    room: str


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
        pairs.append(Pair(start, end, event.get("title", "Без названия"),
                          event.get("loadType", ""), event.get("auditoryTitle") or ""))
    return sorted(pairs, key=lambda pair: pair.start)


class Schedule:
    """Расписание на две недели; обновляется не чаще раза в 10 минут."""

    def __init__(self) -> None:
        self._pairs: list[Pair] = []
        self._fetched: datetime | None = None

    async def pairs(self) -> list[Pair]:
        now = datetime.now(TZ)
        if self._fetched is None or now - self._fetched > timedelta(minutes=10):
            self._pairs = await self._fetch(now.date())
            self._fetched = now
        return self._pairs

    async def _fetch(self, today: date) -> list[Pair]:
        params = {"date_gte": today.isoformat(), "date_lte": (today + timedelta(days=14)).isoformat()}
        timeout = aiohttp.ClientTimeout(total=20)
        async with aiohttp.ClientSession(headers=HEADERS, timeout=timeout) as session:
            async with session.get(f"{API}/{GROUP_ID}/schedule/", params=params) as response:
                response.raise_for_status()
                data = await response.json(content_type=None)
        return parse_pairs(data.get("events", []))


schedule = Schedule()


def fmt_pair(pair: Pair) -> str:
    room = f" · {html.escape(pair.room)}" if pair.room else ""
    kind = f" ({html.escape(pair.kind)})" if pair.kind else ""
    return f"{E_CLOCK} <b>{pair.start:%H:%M}–{pair.end:%H:%M}</b> {html.escape(pair.title)}{kind}{room}"


def day_block(day: date, pairs: list[Pair]) -> str:
    head = f"{E_CALENDAR} <b>{day:%d.%m} {WEEKDAYS[day.weekday()]}</b>"
    if not pairs:
        return f"{head}\n{E_EMPTY} Пар нет"
    return "\n".join([head, *(fmt_pair(pair) for pair in pairs)])


async def pairs_on(day: date) -> list[Pair]:
    return [pair for pair in await schedule.pairs() if pair.start.date() == day]


@dp.message(Command("start"))
async def start(message: Message) -> None:
    if not ALLOWED:
        await message.answer(f"{E_INFO} Ваш chat id: <code>{message.chat.id}</code>. "
                             "Добавьте его в ALLOWED_CHAT_IDS и перезапустите бота.")
    elif message.chat.id not in ALLOWED:
        await message.answer(f"{E_LOCK} Бот личный.")
    else:
        await message.answer(f"{E_BOT} Команды: /today — пары сегодня, /next — ближайшая пара, "
                             "/week — на неделю.")


@dp.message(Command("today"), F.chat.id.in_(ALLOWED))
async def today(message: Message) -> None:
    async def text() -> str:
        day = datetime.now(TZ).date()
        return day_block(day, await pairs_on(day))

    await answer_safely(message, text)


@dp.message(Command("next"), F.chat.id.in_(ALLOWED))
async def next_pair(message: Message) -> None:
    async def text() -> str:
        now = datetime.now(TZ)
        pairs = await pairs_on(now.date())
        current = [pair for pair in pairs if pair.start <= now < pair.end]
        upcoming = [pair for pair in pairs if pair.start > now]
        lines = []
        if current:
            lines.append(f"{E_NOW} <b>Сейчас:</b> {fmt_pair(current[0])}")
        if upcoming:
            lines.append(f"{E_NEXT} <b>Дальше:</b> {fmt_pair(upcoming[0])}")
        return "\n".join(lines) or f"{E_DONE} Сегодня пар больше нет"

    await answer_safely(message, text)


@dp.message(Command("week"), F.chat.id.in_(ALLOWED))
async def week(message: Message) -> None:
    async def text() -> str:
        today_ = datetime.now(TZ).date()
        blocks = []
        for offset in range(7):
            day = today_ + timedelta(days=offset)
            pairs = await pairs_on(day)
            if pairs:
                blocks.append(day_block(day, pairs))
        return "\n\n".join(blocks) or f"{E_EMPTY} На неделю пар нет"

    await answer_safely(message, text)


async def answer_safely(message: Message, build) -> None:
    try:
        await message.answer(await build())
    except Exception:
        log.exception("schedule request failed")
        await message.answer(f"{E_WARN} Не получилось загрузить расписание. Попробуйте позже.")


async def reminder_loop(bot: Bot) -> None:
    """Напоминает о каждой паре за REMIND_MINUTES минут до начала, один раз."""
    sent: set[str] = set()
    while True:
        try:
            now = datetime.now(TZ)
            for pair in await schedule.pairs():
                key = pair.start.isoformat()
                if key in sent or not timedelta(0) <= pair.start - now <= timedelta(minutes=REMIND_MINUTES):
                    continue
                sent.add(key)
                for chat_id in ALLOWED:
                    await bot.send_message(chat_id, f"{E_BELL} Через {REMIND_MINUTES} мин: {fmt_pair(pair)}")
        except Exception:
            log.exception("reminder check failed")
        await asyncio.sleep(60)


async def digest_loop(bot: Bot) -> None:
    """Утром в DIGEST_HOUR присылает расписание дня."""
    last_sent: date | None = None
    while True:
        try:
            now = datetime.now(TZ)
            if now.hour == DIGEST_HOUR and last_sent != now.date():
                last_sent = now.date()
                text = day_block(now.date(), await pairs_on(now.date()))
                for chat_id in ALLOWED:
                    await bot.send_message(chat_id, f"{E_SUN} Доброе утро!\n\n{text}")
        except Exception:
            log.exception("digest failed")
        await asyncio.sleep(60)


async def main() -> None:
    logging.basicConfig(level=logging.INFO)
    bot = Bot(BOT_TOKEN, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    await bot.set_my_commands([
        BotCommand(command="today", description="Пары сегодня"),
        BotCommand(command="next", description="Ближайшая пара"),
        BotCommand(command="week", description="Пары на неделю"),
    ])
    tasks = [asyncio.create_task(reminder_loop(bot)), asyncio.create_task(digest_loop(bot))]
    try:
        await dp.start_polling(bot)
    finally:
        for task in tasks:
            task.cancel()


if __name__ == "__main__":
    asyncio.run(main())
