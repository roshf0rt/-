"""Rich-сообщения (sendRichMessage): текст собирается из блоков, а не из HTML-тегов.

Если Telegram отклонит rich-сообщение, бот пришлёт тот же текст обычным сообщением: см. plain_blocks().
"""
import aiohttp

# Премиум-эмодзи: ID из гайда emoji.wivvi.net, запасной обычный эмодзи.
ICONS = {
    "calendar": ("5890937706803894250", "📅"),
    "clock": ("5983150113483134607", "⏰"),
    "now": ("5773626993010546707", "▶️"),
    "next": ("6037622221625626773", "➡️"),
    "done": ("6041731551845159060", "🎉"),
    "empty": ("5983401171501454028", "💤"),
    "bot": ("6030400221232501136", "🤖"),
    "lock": ("6037249452824072506", "🔒"),
    "info": ("6028435952299413210", "ℹ️"),
    "bell": ("6039677157318332604", "🔔"),
    "sun": ("5938525265838739643", "☀️"),
    "warn": ("6030563507299160824", "❗️"),
    "list": ("5766994197705921104", "🗂"),
}


def icon(name: str) -> dict:
    emoji_id, fallback = ICONS[name]
    return {"type": "custom_emoji", "custom_emoji_id": emoji_id, "alternative_text": fallback}


def bold(text) -> dict:
    return {"type": "bold", "text": text}


def code(text: str) -> dict:
    return {"type": "code", "text": text}


def paragraph(*parts) -> dict:
    return {"type": "paragraph", "text": list(parts)}


def heading(parts: list, size: int) -> dict:
    return {"type": "heading", "text": parts, "size": size}


def plain_text(value) -> str:
    """Текст без форматирования: для запасного сообщения и для подписей."""
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        return "".join(plain_text(part) for part in value)
    if value["type"] == "custom_emoji":
        return value["alternative_text"]
    return plain_text(value["text"])


def block_plain(block: dict) -> str:
    kind = block["type"]
    if kind in ("paragraph", "heading", "expandable_blockquote", "footer"):
        return plain_text(block["text"])
    if kind == "blockquote":
        return plain_blocks(block["blocks"])
    if kind == "list":
        return "\n".join("• " + plain_blocks(item["blocks"]) for item in block["items"])
    return ""


def plain_blocks(blocks: list[dict]) -> str:
    return "\n".join(text for text in (block_plain(block) for block in blocks) if text)


def table(rows: list[list[str]], caption: str) -> dict:
    """Таблица: первая строка — заголовок. Текст ячеек обычный, без форматирования."""
    cells = [[{"text": cell, "is_header": row_index == 0, "align": "left", "valign": "middle"}
              for cell in row] for row_index, row in enumerate(rows)]
    return {"type": "table", "cells": cells, "caption": caption,
            "is_bordered": True, "is_striped": True, "is_compact": True}


async def send(token: str, chat_id: int, blocks: list[dict]) -> None:
    """Отправляет rich-сообщение; при ошибке Telegram бросает исключение."""
    body = {"chat_id": chat_id, "rich_message": {"blocks": blocks}}
    async with aiohttp.ClientSession() as session:
        async with session.post(f"https://api.telegram.org/bot{token}/sendRichMessage", json=body) as response:
            data = await response.json(content_type=None)
    if not data.get("ok"):
        raise RuntimeError(f"sendRichMessage failed: {data.get('description')}")
