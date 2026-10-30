"""Настройки пользователей в SQLite. Один файл, без отдельного сервера базы."""
import sqlite3
from dataclasses import dataclass

# Как в приложении: «напоминать за N минут» и «выключено».
REMIND_CHOICES = [0, 5, 10, 15, 20, 30]


@dataclass(frozen=True)
class User:
    chat_id: int
    group_id: str | None
    group_name: str | None
    subgroup: int | None
    remind_minutes: int
    digest: bool
    dayend: bool
    after_pair: bool
    last_digest: str | None


class Store:
    def __init__(self, path: str) -> None:
        self.db = sqlite3.connect(path)
        self.db.row_factory = sqlite3.Row
        self.db.execute(
            """CREATE TABLE IF NOT EXISTS users (
                chat_id INTEGER PRIMARY KEY,
                group_id TEXT,
                group_name TEXT,
                subgroup INTEGER,
                remind_minutes INTEGER NOT NULL DEFAULT 10,
                digest INTEGER NOT NULL DEFAULT 1,
                dayend INTEGER NOT NULL DEFAULT 0,
                last_digest TEXT
            )"""
        )
        # Колонку добавили позже: в старой базе её нет.
        columns = {row["name"] for row in self.db.execute("PRAGMA table_info(users)")}
        if "after_pair" not in columns:
            self.db.execute("ALTER TABLE users ADD COLUMN after_pair INTEGER NOT NULL DEFAULT 0")
        self.db.commit()

    @staticmethod
    def _user(row: sqlite3.Row) -> User:
        return User(row["chat_id"], row["group_id"], row["group_name"], row["subgroup"],
                    row["remind_minutes"], bool(row["digest"]), bool(row["dayend"]),
                    bool(row["after_pair"]), row["last_digest"])

    def get(self, chat_id: int) -> User | None:
        row = self.db.execute("SELECT * FROM users WHERE chat_id = ?", (chat_id,)).fetchone()
        return self._user(row) if row else None

    def ensure(self, chat_id: int) -> None:
        self.db.execute("INSERT OR IGNORE INTO users (chat_id) VALUES (?)", (chat_id,))
        self.db.commit()

    def update(self, chat_id: int, **fields) -> None:
        # Имена полей задаёт только код бота, не пользователь.
        assignments = ", ".join(f"{name} = ?" for name in fields)
        self.db.execute(f"UPDATE users SET {assignments} WHERE chat_id = ?", (*fields.values(), chat_id))
        self.db.commit()

    def delete(self, chat_id: int) -> None:
        self.db.execute("DELETE FROM users WHERE chat_id = ?", (chat_id,))
        self.db.commit()

    def with_group(self) -> list[User]:
        rows = self.db.execute("SELECT * FROM users WHERE group_id IS NOT NULL").fetchall()
        return [self._user(row) for row in rows]
