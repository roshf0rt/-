"""Telegram-бот с расписанием групп УрФУ. Каждый пользователь выбирает свою группу и подгруппу.

Настройки повторяют приложение: группа, подгруппа, напоминание до пары,
сообщение, когда пары кончились (и про каникулы). Плюс утренняя сводка.
"""
import asyncio
import html
import logging
import os
from datetime import date, datetime, timedelta

from aiogram import Bot, Dispatcher, F
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.exceptions import TelegramBadRequest
from aiogram.filters import Command, CommandStart
from aiogram.types import (BotCommand, CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message)

import urfu
from store import REMIND_CHOICES, Store, User
from urfu import TZ, Pair

BOT_TOKEN = os.environ["BOT_TOKEN"]
DB_PATH = os.environ.get("DB_PATH", "bot.db")
DIGEST_HOUR = int(os.environ.get("DIGEST_HOUR", "8"))

WEEKDAYS = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]
# Фразы из приложения (Shared/Mood.swift).
DAY_DONE_LINES = [
    "Ура, пары закончились! 🎉",
    "Всё, учёба на сегодня окончена 🥳",
    "Свободны! Мозг просит перерыв 🧠",
    "Пары кончились, можно выдохнуть 😌",
    "Отбой по парам. Гуляйте 🚶",
    "Газ домой! 🏠",
]
VACATION_LINES = [
    "Каникулы! Пары отдыхают 🏖️",
    "Расписание в отпуске. Вы тоже 🌴",
    "Каникулы — это не миф, это вы 😎",
]
VACATION_GAP = timedelta(days=10)


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

WELCOME = (f"{E_BOT} <b>Привет!</b> Я присылаю расписание группы УрФУ.\n\n"
           "Напишите номер группы, например <code>433505</code>.\n\n"
           "Потом: /today, /next, /week, /settings.\n\n"
           "Бот хранит chat id, группу и подгруппу. Удалить всё — /delete.")
NEED_GROUP = f"{E_INFO} Сначала выберите группу: напишите её номер, например 433505."

log = logging.getLogger("urfu-bot")
store = Store(DB_PATH)
dp = Dispatcher()
_cache: dict[str, tuple[datetime, list[Pair]]] = {}


async def pairs_for(group_id: str) -> list[Pair]:
    """Расписание группы на две недели. Общее для всех пользователей группы, обновляется раз в 10 минут."""
    now = datetime.now(TZ)
    cached = _cache.get(group_id)
    if cached and now - cached[0] < timedelta(minutes=10):
        return cached[1]
    pairs = await urfu.fetch_pairs(group_id, now.date())
    _cache[group_id] = (now, pairs)
    return pairs


def visible(pairs: list[Pair], subgroup: int | None) -> list[Pair]:
    return [pair for pair in pairs if subgroup is None or pair.subgroup in (None, subgroup)]


async def day_pairs(user: User, day: date) -> list[Pair]:
    return [pair for pair in visible(await pairs_for(user.group_id), user.subgroup) if pair.start.date() == day]


def fmt_pair(pair: Pair) -> str:
    room = f" · {html.escape(pair.room)}" if pair.room else ""
    kind = f" ({html.escape(pair.kind)})" if pair.kind else ""
    return f"{E_CLOCK} <b>{pair.start:%H:%M}–{pair.end:%H:%M}</b> {html.escape(pair.title)}{kind}{room}"


def day_block(day: date, pairs: list[Pair]) -> str:
    head = f"{E_CALENDAR} <b>{day:%d.%m} {WEEKDAYS[day.weekday()]}</b>"
    if not pairs:
        return f"{head}\n{E_EMPTY} Пар нет"
    return "\n".join([head, *(fmt_pair(pair) for pair in pairs)])


def line(lines: list[str], day: date) -> str:
    return lines[day.toordinal() % len(lines)]


def subgroup_label(subgroup: int | None) -> str:
    return "все пары" if subgroup is None else f"{subgroup} подгруппа"


def subgroup_keyboard() -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[[
        InlineKeyboardButton(text="Все пары", callback_data="sg:all"),
        InlineKeyboardButton(text="1", callback_data="sg:1"),
        InlineKeyboardButton(text="2", callback_data="sg:2"),
    ]])


def settings_view(user: User) -> tuple[str, InlineKeyboardMarkup]:
    remind = f"Напоминать за {user.remind_minutes} мин" if user.remind_minutes else "Напоминания выкл"
    digest = "вкл" if user.digest else "выкл"
    dayend = "вкл" if user.dayend else "выкл"
    text = (f"{E_BOT} <b>Настройки</b>\n"
            f"Группа: {html.escape(user.group_name or '—')}\n"
            f"Подгруппа: {subgroup_label(user.subgroup)}")
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=remind, callback_data="st:remind")],
        [InlineKeyboardButton(text=f"Утренняя сводка: {digest}", callback_data="st:digest")],
        [InlineKeyboardButton(text=f"Пары кончились: {dayend}", callback_data="st:dayend")],
        [InlineKeyboardButton(text="Сменить подгруппу", callback_data="st:sub")],
        [InlineKeyboardButton(text="Удалить мои данные", callback_data="st:delete")],
    ])
    return text, keyboard


def user_with_group(chat_id: int) -> User | None:
    user = store.get(chat_id)
    return user if user and user.group_id else None


async def show(cb: CallbackQuery, text: str, keyboard: InlineKeyboardMarkup | None) -> None:
    try:
        await cb.message.edit_text(text, reply_markup=keyboard)
    except TelegramBadRequest:
        pass  # текст не изменился


async def answer_schedule(message: Message, build) -> None:
    user = user_with_group(message.chat.id)
    if user is None:
        await message.answer(NEED_GROUP)
        return
    try:
        await message.answer(await build(user))
    except Exception:
        log.exception("schedule request failed")
        await message.answer(f"{E_WARN} Не получилось загрузить расписание. Попробуйте позже.")


# ---------- команды ----------

@dp.message(CommandStart())
async def start(message: Message) -> None:
    store.ensure(message.chat.id)
    await message.answer(WELCOME)


@dp.message(Command("group"))
async def group(message: Message) -> None:
    store.ensure(message.chat.id)
    await message.answer("Напишите номер группы, например 433505.")


@dp.message(Command("subgroup"))
async def subgroup(message: Message) -> None:
    if user_with_group(message.chat.id) is None:
        await message.answer(NEED_GROUP)
        return
    await message.answer("Выберите подгруппу:", reply_markup=subgroup_keyboard())


@dp.message(Command("settings"))
async def settings(message: Message) -> None:
    user = user_with_group(message.chat.id)
    if user is None:
        await message.answer(NEED_GROUP)
        return
    text, keyboard = settings_view(user)
    await message.answer(text, reply_markup=keyboard)


@dp.message(Command("delete"))
async def delete(message: Message) -> None:
    store.delete(message.chat.id)
    await message.answer("Данные удалены. Напишите /start, чтобы начать заново.")


@dp.message(Command("today"))
async def today(message: Message) -> None:
    async def text(user: User) -> str:
        day = datetime.now(TZ).date()
        return day_block(day, await day_pairs(user, day))

    await answer_schedule(message, text)


@dp.message(Command("next"))
async def next_pair(message: Message) -> None:
    async def text(user: User) -> str:
        now = datetime.now(TZ)
        pairs = await day_pairs(user, now.date())
        current = [pair for pair in pairs if pair.start <= now < pair.end]
        upcoming = [pair for pair in pairs if pair.start > now]
        lines = []
        if current:
            lines.append(f"{E_NOW} <b>Сейчас:</b> {fmt_pair(current[0])}")
        if upcoming:
            lines.append(f"{E_NEXT} <b>Дальше:</b> {fmt_pair(upcoming[0])}")
        return "\n".join(lines) or f"{E_DONE} Сегодня пар больше нет"

    await answer_schedule(message, text)


@dp.message(Command("week"))
async def week(message: Message) -> None:
    async def text(user: User) -> str:
        today_ = datetime.now(TZ).date()
        blocks = []
        for offset in range(7):
            day = today_ + timedelta(days=offset)
            pairs = await day_pairs(user, day)
            if pairs:
                blocks.append(f"<blockquote expandable>{day_block(day, pairs)}</blockquote>")
        return "\n\n".join(blocks) or f"{E_EMPTY} На неделю пар нет"

    await answer_schedule(message, text)


# ---------- ввод номера группы ----------

@dp.message(F.text)
async def search_group(message: Message) -> None:
    query = message.text.strip()
    if query.startswith("/"):
        return
    store.ensure(message.chat.id)
    if not query or len(query) > 20:
        await message.answer("Напишите номер группы, например 433505.")
        return
    try:
        groups = await urfu.search_groups(query)
    except Exception:
        log.exception("group search failed")
        await message.answer(f"{E_WARN} Не получилось найти группы. Попробуйте позже.")
        return
    if not groups:
        await message.answer(f"{E_LIST} Группа «{html.escape(query)}» не найдена. Проверьте номер.")
        return
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=group.name, callback_data=f"g:{group.id}:{group.name}"[:64])]
        for group in groups
    ])
    await message.answer(f"{E_LIST} Выберите группу:", reply_markup=keyboard)


# ---------- кнопки ----------

@dp.callback_query(F.data.startswith("g:"))
async def pick_group(cb: CallbackQuery) -> None:
    _, group_id, name = cb.data.split(":", 2)
    chat_id = cb.message.chat.id
    store.ensure(chat_id)
    store.update(chat_id, group_id=group_id, group_name=name, subgroup=None)
    await show(cb, f"{E_CALENDAR} Группа {html.escape(name)}. Выберите подгруппу:", subgroup_keyboard())
    await cb.answer()


@dp.callback_query(F.data.startswith("sg:"))
async def pick_subgroup(cb: CallbackQuery) -> None:
    value = cb.data.split(":")[1]
    chat_id = cb.message.chat.id
    store.update(chat_id, subgroup=None if value == "all" else int(value))
    text, keyboard = settings_view(store.get(chat_id))
    await show(cb, text, keyboard)
    await cb.answer("Сохранено")


@dp.callback_query(F.data.startswith("st:"))
async def settings_action(cb: CallbackQuery) -> None:
    chat_id = cb.message.chat.id
    user = user_with_group(chat_id)
    if user is None:
        await cb.answer("Сначала выберите группу", show_alert=True)
        return
    action = cb.data.split(":")[1]
    if action == "remind":
        index = REMIND_CHOICES.index(user.remind_minutes) if user.remind_minutes in REMIND_CHOICES else 0
        store.update(chat_id, remind_minutes=REMIND_CHOICES[(index + 1) % len(REMIND_CHOICES)])
    elif action == "digest":
        store.update(chat_id, digest=int(not user.digest))
    elif action == "dayend":
        store.update(chat_id, dayend=int(not user.dayend))
    elif action == "sub":
        await show(cb, "Выберите подгруппу:", subgroup_keyboard())
        await cb.answer()
        return
    elif action == "delete":
        store.delete(chat_id)
        await show(cb, "Данные удалены. Напишите /start, чтобы начать заново.", None)
        await cb.answer()
        return
    text, keyboard = settings_view(store.get(chat_id))
    await show(cb, text, keyboard)
    await cb.answer()


# ---------- фоновые рассылки ----------

async def send(bot: Bot, chat_id: int, text: str) -> None:
    try:
        await bot.send_message(chat_id, text)
    except Exception:
        log.exception("send to %s failed", chat_id)
    await asyncio.sleep(0.05)  # не упираться в лимиты Telegram на рассылку


async def reminder_loop(bot: Bot) -> None:
    """За N минут до каждой пары — один раз."""
    sent: set[str] = set()
    while True:
        try:
            now = datetime.now(TZ)
            for user in store.with_group():
                if not user.remind_minutes:
                    continue
                lead = timedelta(minutes=user.remind_minutes)
                for pair in visible(await pairs_for(user.group_id), user.subgroup):
                    key = f"{user.chat_id}:{pair.start.isoformat()}"
                    if key in sent or not timedelta(0) <= pair.start - now <= lead:
                        continue
                    sent.add(key)
                    await send(bot, user.chat_id,
                               f"{E_BELL} Через {user.remind_minutes} мин: {fmt_pair(pair)}")
            if len(sent) > 5000:
                sent.clear()
        except Exception:
            log.exception("reminder check failed")
        await asyncio.sleep(60)


async def digest_loop(bot: Bot) -> None:
    """Утренняя сводка на день в DIGEST_HOUR."""
    while True:
        try:
            now = datetime.now(TZ)
            today_ = now.date().isoformat()
            for user in store.with_group():
                if not user.digest or now.hour != DIGEST_HOUR or user.last_digest == today_:
                    continue
                store.update(user.chat_id, last_digest=today_)
                pairs = await day_pairs(user, now.date())
                await send(bot, user.chat_id, f"{E_SUN} Доброе утро!\n\n{day_block(now.date(), pairs)}")
        except Exception:
            log.exception("digest failed")
        await asyncio.sleep(60)


async def dayend_loop(bot: Bot) -> None:
    """Сразу после последней пары дня — весёлая фраза или сообщение про каникулы."""
    sent: set[str] = set()
    while True:
        try:
            now = datetime.now(TZ)
            for user in store.with_group():
                if not user.dayend:
                    continue
                pairs = await day_pairs(user, now.date())
                if not pairs:
                    continue
                last_end = max(pair.end for pair in pairs)
                # Только в первые 10 минут после конца: после перезапуска старые сообщения не шлём.
                if not timedelta(0) <= now - last_end <= timedelta(minutes=10):
                    continue
                key = f"{user.chat_id}:{now.date().isoformat()}"
                if key in sent:
                    continue
                sent.add(key)
                upcoming = [pair for pair in visible(await pairs_for(user.group_id), user.subgroup)
                            if pair.start > now]
                if upcoming and upcoming[0].start - now >= VACATION_GAP:
                    text = f"🤙 {line(VACATION_LINES, now.date())}"
                else:
                    text = line(DAY_DONE_LINES, now.date())
                await send(bot, user.chat_id, text)
            sent = {key for key in sent if key.endswith(now.date().isoformat())}
        except Exception:
            log.exception("day end check failed")
        await asyncio.sleep(60)


async def main() -> None:
    logging.basicConfig(level=logging.INFO)
    bot = Bot(BOT_TOKEN, default=DefaultBotProperties(parse_mode=ParseMode.HTML))
    await bot.set_my_commands([
        BotCommand(command="today", description="Пары сегодня"),
        BotCommand(command="next", description="Ближайшая пара"),
        BotCommand(command="week", description="Пары на неделю"),
        BotCommand(command="group", description="Выбрать группу"),
        BotCommand(command="subgroup", description="Выбрать подгруппу"),
        BotCommand(command="settings", description="Настройки"),
        BotCommand(command="delete", description="Удалить мои данные"),
    ])
    tasks = [asyncio.create_task(loop(bot)) for loop in (reminder_loop, digest_loop, dayend_loop)]
    try:
        await dp.start_polling(bot)
    finally:
        for task in tasks:
            task.cancel()


if __name__ == "__main__":
    asyncio.run(main())
