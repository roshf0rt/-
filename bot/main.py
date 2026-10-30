"""Telegram-бот с расписанием групп УрФУ. Каждый пользователь выбирает свою группу и подгруппу.

Настройки повторяют приложение: группа, подгруппа, напоминание до пары,
сообщение, когда пары кончились (и про каникулы). Плюс утренняя сводка.

Сообщения с расписанием и уведомления идут rich-блоками (см. rich.py).
Сообщения с кнопками остаются обычным HTML-текстом.
"""
import asyncio
import html
import logging
import os
from datetime import date, datetime, timedelta
from urllib.parse import quote

from aiogram import Bot, Dispatcher, F
from aiogram.client.default import DefaultBotProperties
from aiogram.enums import ParseMode
from aiogram.exceptions import TelegramBadRequest
from aiogram.filters import Command, CommandStart
from aiogram.types import (BotCommand, CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message,
                           URLInputFile)

import rich
import urfu
from rich import bold, code, heading, icon, paragraph
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

# Весёлые фразы: выбираются по дню, чтобы не повторялись каждый день.
MORNING_LINES = [
    "Доброе утро, котята! ☕",
    "Котята, подъём! Пары ждут 🐾",
    "Утро-утро, кофе и вперёд ☀️",
    "Доброе утро, мои пушистые студенты 🐱",
]
CHILL_LINES = [
    "Сегодня пар нет, чилл на расслабоне 😎",
    "Пар нет. Котята отдыхают 🛋️",
    "Сегодня без пар, расслабон включён 🌴",
]
# Подписи к картинкам с котами (cataas.com). Короткие, чтобы влезли на картинку.
MORNING_MEMES = ["Доброе утро котята", "Котята подъем", "Утро кофе пары"]
CHILL_MEMES = ["Пар нет", "Чилл на расслабоне", "Котята отдыхают"]
DONE_MEMES = ["Пары кончились", "Газ домой котята", "Свободны котята"]
VACATION_MEMES = ["Каникулы котята", "Котята на каникулах"]
CAT_API = "https://cataas.com/cat/says/{text}?fontSize=60&fontColor=white"

WELCOME = [
    paragraph(icon("bot"), " ", bold("Привет!"), " Я присылаю расписание группы УрФУ."),
    paragraph("Напишите номер группы, например ", code("433505"), "."),
    paragraph("Потом: /today, /next, /week, /settings."),
    paragraph("Бот хранит chat id, группу и подгруппу. Удалить всё — /delete."),
]
NEED_GROUP = [paragraph(icon("info"), " Сначала выберите группу: напишите её номер, например ", code("433505"), ".")]
GROUP_PROMPT = [paragraph("Напишите номер группы, например ", code("433505"), ".")]
SEARCH_FAILED = [paragraph(icon("warn"), " Не получилось найти группы. Попробуйте позже.")]
SCHEDULE_FAILED = [paragraph(icon("warn"), " Не получилось загрузить расписание. Попробуйте позже.")]

log = logging.getLogger("urfu-bot")
store = Store(DB_PATH)
dp = Dispatcher()
_cache: dict[str, tuple[datetime, list[Pair]]] = {}


def html_icon(name: str) -> str:
    """Премиум-эмодзи для HTML-текста (сообщения с кнопками)."""
    emoji_id, fallback = rich.ICONS[name]
    return f'<tg-emoji emoji-id="{emoji_id}">{fallback}</tg-emoji>'


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


def pair_text(pair: Pair) -> list:
    """Строка пары: время жирным, затем предмет, тип занятия и кабинет."""
    kind = f" ({pair.kind})" if pair.kind else ""
    room = f" · {pair.room}" if pair.room else ""
    return [bold(f"{pair.start:%H:%M}–{pair.end:%H:%M}"), f" {pair.title}{kind}{room}"]


def day_blocks(day: date, pairs: list[Pair]) -> list[dict]:
    title = heading([icon("calendar"), f" {day:%d.%m} {WEEKDAYS[day.weekday()]}"], 3)
    if not pairs:
        return [title, paragraph(icon("empty"), " ", line(CHILL_LINES, day))]
    return [title, *(paragraph(icon("clock"), " ", *pair_text(pair)) for pair in pairs)]


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
    after = "вкл" if user.after_pair else "выкл"
    text =(f"{html_icon('bot')} <b>Настройки</b>\n"
            f"Группа: {html.escape(user.group_name or '—')}\n"
            f"Подгруппа: {subgroup_label(user.subgroup)}")
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=remind, callback_data="st:remind")],
        [InlineKeyboardButton(text=f"Утренняя сводка: {digest}", callback_data="st:digest")],
        [InlineKeyboardButton(text=f"Пары кончились: {dayend}", callback_data="st:dayend")],
        [InlineKeyboardButton(text=f"После пары — что дальше: {after}", callback_data="st:after")],
        [InlineKeyboardButton(text="Сменить подгруппу", callback_data="st:sub")],
        [InlineKeyboardButton(text="Удалить мои данные", callback_data="st:delete")],
    ])
    return text, keyboard


def user_with_group(chat_id: int) -> User | None:
    user = store.get(chat_id)
    return user if user and user.group_id else None


async def deliver(bot: Bot, chat_id: int, blocks: list[dict]) -> None:
    """Rich-сообщение; если Telegram не принял его, тот же текст обычным сообщением."""
    try:
        await rich.send(BOT_TOKEN, chat_id, blocks)
    except Exception:
        log.exception("rich message failed, sending plain text")
        await bot.send_message(chat_id, html.escape(rich.plain_blocks(blocks)))


async def show(cb: CallbackQuery, text: str, keyboard: InlineKeyboardMarkup | None) -> None:
    try:
        await cb.message.edit_text(text, reply_markup=keyboard)
    except TelegramBadRequest:
        pass  # текст не изменился


async def answer_schedule(message: Message, build) -> None:
    user = user_with_group(message.chat.id)
    if user is None:
        await deliver(message.bot, message.chat.id, NEED_GROUP)
        return
    try:
        blocks = await build(user)
    except Exception:
        log.exception("schedule request failed")
        blocks = SCHEDULE_FAILED
    await deliver(message.bot, message.chat.id, blocks)


# ---------- команды ----------

@dp.message(CommandStart())
async def start(message: Message) -> None:
    store.ensure(message.chat.id)
    await deliver(message.bot, message.chat.id, WELCOME)


@dp.message(Command("group"))
async def group(message: Message) -> None:
    store.ensure(message.chat.id)
    await deliver(message.bot, message.chat.id, GROUP_PROMPT)


@dp.message(Command("subgroup"))
async def subgroup(message: Message) -> None:
    if user_with_group(message.chat.id) is None:
        await deliver(message.bot, message.chat.id, NEED_GROUP)
        return
    await message.answer("Выберите подгруппу:", reply_markup=subgroup_keyboard())


@dp.message(Command("settings"))
async def settings(message: Message) -> None:
    user = user_with_group(message.chat.id)
    if user is None:
        await deliver(message.bot, message.chat.id, NEED_GROUP)
        return
    text, keyboard = settings_view(user)
    await message.answer(text, reply_markup=keyboard)


@dp.message(Command("delete"))
async def delete(message: Message) -> None:
    store.delete(message.chat.id)
    await deliver(message.bot, message.chat.id, [paragraph("Данные удалены. Напишите /start, чтобы начать заново.")])


@dp.message(Command("today"))
async def today(message: Message) -> None:
    async def blocks(user: User) -> list[dict]:
        day = datetime.now(TZ).date()
        return day_blocks(day, await day_pairs(user, day))

    await answer_schedule(message, blocks)


@dp.message(Command("next"))
async def next_pair(message: Message) -> None:
    async def blocks(user: User) -> list[dict]:
        now = datetime.now(TZ)
        pairs = await day_pairs(user, now.date())
        current = [pair for pair in pairs if pair.start <= now < pair.end]
        upcoming = [pair for pair in pairs if pair.start > now]
        result = []
        if current:
            result.append(paragraph(icon("now"), " ", bold("Сейчас: "), *pair_text(current[0])))
        if upcoming:
            result.append(paragraph(icon("next"), " ", bold("Дальше: "), *pair_text(upcoming[0])))
        return result or [paragraph(icon("done"), " Сегодня пар больше нет")]

    await answer_schedule(message, blocks)


@dp.message(Command("week"))
async def week(message: Message) -> None:
    user = user_with_group(message.chat.id)
    if user is None:
        await deliver(message.bot, message.chat.id, NEED_GROUP)
        return
    today_ = datetime.now(TZ).date()
    rows = [["День", "Время", "Предмет", "Ауд."]]
    days = []
    for offset in range(7):
        day = today_ + timedelta(days=offset)
        pairs = await day_pairs(user, day)
        for pair in pairs:
            rows.append([f"{day:%d.%m} {WEEKDAYS[day.weekday()]}", f"{pair.start:%H:%M}–{pair.end:%H:%M}",
                         pair.title, pair.room or "—"])
        if pairs:
            days.extend(day_blocks(day, pairs))
    if len(rows) == 1:
        await deliver(message.bot, message.chat.id, [paragraph(icon("empty"), " На неделю пар нет")])
        return
    try:
        await rich.send(BOT_TOKEN, message.chat.id, [rich.table(rows, "Расписание на неделю")])
    except Exception:
        # Таблица не ушла: присылаем дни списком, тоже rich-блоками.
        log.exception("rich table failed, falling back to day list")
        await deliver(message.bot, message.chat.id, days)


# ---------- ввод номера группы ----------

@dp.message(F.text)
async def search_group(message: Message) -> None:
    query = message.text.strip()
    if query.startswith("/"):
        return
    store.ensure(message.chat.id)
    if not query or len(query) > 20:
        await deliver(message.bot, message.chat.id, GROUP_PROMPT)
        return
    try:
        groups = await urfu.search_groups(query)
    except Exception:
        log.exception("group search failed")
        await deliver(message.bot, message.chat.id, SEARCH_FAILED)
        return
    if not groups:
        await deliver(message.bot, message.chat.id,
                      [paragraph(icon("list"), f" Группа «{query}» не найдена. Проверьте номер.")])
        return
    keyboard = InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=group.name, callback_data=f"g:{group.id}:{group.name}"[:64])]
        for group in groups
    ])
    await message.answer(f"{html_icon('list')} Выберите группу:", reply_markup=keyboard)


# ---------- кнопки ----------

@dp.callback_query(F.data.startswith("g:"))
async def pick_group(cb: CallbackQuery) -> None:
    _, group_id, name = cb.data.split(":", 2)
    chat_id = cb.message.chat.id
    store.ensure(chat_id)
    store.update(chat_id, group_id=group_id, group_name=name, subgroup=None)
    await show(cb, f"{html_icon('calendar')} Группа {html.escape(name)}. Выберите подгруппу:", subgroup_keyboard())
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
    elif action == "after":
        store.update(chat_id, after_pair=int(not user.after_pair))
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
                    await deliver(bot, user.chat_id,
                                  [paragraph(icon("bell"), f" Через {user.remind_minutes} мин: ", *pair_text(pair))])
                    await asyncio.sleep(0.05)  # не упираться в лимиты Telegram на рассылку
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
                await send_cat(bot, user.chat_id, line(MORNING_MEMES if pairs else CHILL_MEMES, now.date()))
                await deliver(bot, user.chat_id,
                              [heading([line(MORNING_LINES, now.date())], 2), *day_blocks(now.date(), pairs)])
                await asyncio.sleep(0.05)
        except Exception:
            log.exception("digest failed")
        await asyncio.sleep(60)


async def send_cat(bot: Bot, chat_id: int, text: str) -> None:
    """Картинка с котом и подписью. Если сервис не ответил, просто пропускаем картинку."""
    try:
        await bot.send_photo(chat_id, URLInputFile(CAT_API.format(text=quote(text)), filename="cat.jpg"))
    except Exception:
        log.exception("cat picture failed")


def after_pair_blocks(now: datetime, nxt: Pair) -> list[dict]:
    minutes = int((nxt.start - now).total_seconds() // 60)
    when = f"Через {minutes} мин." if minutes > 0 else "Уже начинается."
    return [
        paragraph(icon("next"), " Пара закончилась. Дальше: ", *pair_text(nxt)),
        paragraph(f"{when} Успеете перекусить? ☕"),
    ]


async def send_day_end(bot: Bot, user: User, now: datetime) -> None:
    upcoming = [pair for pair in visible(await pairs_for(user.group_id), user.subgroup) if pair.start > now]
    if upcoming and upcoming[0].start - now >= VACATION_GAP:
        await send_cat(bot, user.chat_id, line(VACATION_MEMES, now.date()))
        blocks = [paragraph("🤙 ", line(VACATION_LINES, now.date()))]
    else:
        await send_cat(bot, user.chat_id, line(DONE_MEMES, now.date()))
        blocks = [paragraph(icon("done"), " ", line(DAY_DONE_LINES, now.date()))]
    await deliver(bot, user.chat_id, blocks)
    await asyncio.sleep(0.05)


async def pair_end_loop(bot: Bot) -> None:
    """Через несколько минут после каждой пары: что дальше, а после последней — конец дня."""
    sent: set[str] = set()
    while True:
        try:
            now = datetime.now(TZ)
            for user in store.with_group():
                if not (user.after_pair or user.dayend):
                    continue
                pairs = await day_pairs(user, now.date())
                for pair in pairs:
                    # Только в первые 10 минут после конца: после перезапуска старые сообщения не шлём.
                    if not timedelta(0) <= now - pair.end <= timedelta(minutes=10):
                        continue
                    key = f"{user.chat_id}:{pair.end.isoformat()}"
                    if key in sent:
                        continue
                    sent.add(key)
                    following = [other for other in pairs if other.start >= pair.end]
                    if following:
                        if user.after_pair:
                            await deliver(bot, user.chat_id, after_pair_blocks(now, following[0]))
                            await asyncio.sleep(0.05)
                    elif user.dayend:
                        await send_day_end(bot, user, now)
            sent = {key for key in sent if now.date().isoformat() in key}
        except Exception:
            log.exception("pair end check failed")
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
    tasks = [asyncio.create_task(loop(bot)) for loop in (reminder_loop, digest_loop, pair_end_loop)]
    try:
        await dp.start_polling(bot)
    finally:
        for task in tasks:
            task.cancel()


if __name__ == "__main__":
    asyncio.run(main())
