import json
import os
import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, Iterator, List, Optional

from aw_core.dirs import get_data_dir


def canonical_json(payload: Any) -> str:
    return json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=True)


def _utcnow() -> str:
    return datetime.now(timezone.utc).isoformat()


class SyncOutbox:
    VERSION = 1

    def __init__(self, testing: bool = False) -> None:
        data_dir = Path(get_data_dir("aw-agent-windows"))
        filename = f"aw-fleet-sync{'-testing' if testing else ''}.v{self.VERSION}.db"
        self.path = data_dir / filename
        self.testing = testing
        self._lock = threading.Lock()

        if testing and self.path.exists():
            os.remove(self.path)

        self._conn = sqlite3.connect(self.path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._conn.execute("PRAGMA foreign_keys = ON")
        self._conn.execute("PRAGMA journal_mode = WAL")
        self._conn.execute("PRAGMA synchronous = NORMAL")
        self._init_db()

    def _init_db(self) -> None:
        with self._conn:
            self._conn.executescript(
                """
                CREATE TABLE IF NOT EXISTS agents (
                    agent_id TEXT PRIMARY KEY,
                    device_id TEXT NOT NULL,
                    device_name TEXT NOT NULL,
                    hostname TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    updated_at TEXT NOT NULL
                );

                CREATE TABLE IF NOT EXISTS streams (
                    stream_id TEXT PRIMARY KEY,
                    agent_id TEXT NOT NULL,
                    bucket_id TEXT NOT NULL,
                    bucket_type TEXT NOT NULL,
                    device_id TEXT NOT NULL,
                    username TEXT,
                    session_id TEXT,
                    bucket_metadata_json TEXT NOT NULL,
                    next_seq INTEGER NOT NULL,
                    last_scan_at TEXT,
                    last_local_event_id INTEGER,
                    last_local_event_checksum TEXT,
                    last_acked_seq INTEGER NOT NULL DEFAULT 0,
                    last_sync_attempt_at TEXT,
                    last_sync_success_at TEXT,
                    FOREIGN KEY (agent_id) REFERENCES agents(agent_id)
                );

                CREATE UNIQUE INDEX IF NOT EXISTS idx_streams_bucket_id
                    ON streams(bucket_id);

                CREATE TABLE IF NOT EXISTS source_event_state (
                    stream_id TEXT NOT NULL,
                    source_event_id INTEGER NOT NULL,
                    source_event_version INTEGER NOT NULL,
                    event_checksum TEXT NOT NULL,
                    last_emitted_seq INTEGER NOT NULL,
                    is_final INTEGER NOT NULL DEFAULT 0,
                    first_seen_at TEXT NOT NULL,
                    last_seen_at TEXT NOT NULL,
                    PRIMARY KEY (stream_id, source_event_id),
                    FOREIGN KEY (stream_id) REFERENCES streams(stream_id)
                );

                CREATE TABLE IF NOT EXISTS outbox_ops (
                    stream_id TEXT NOT NULL,
                    seq INTEGER NOT NULL,
                    op_type TEXT NOT NULL,
                    payload_json TEXT NOT NULL,
                    payload_checksum TEXT NOT NULL,
                    created_at TEXT NOT NULL,
                    acked_at TEXT,
                    PRIMARY KEY (stream_id, seq),
                    FOREIGN KEY (stream_id) REFERENCES streams(stream_id)
                );

                CREATE INDEX IF NOT EXISTS idx_outbox_unacked
                    ON outbox_ops(stream_id, acked_at, seq);
                """
            )

    @contextmanager
    def transaction(self) -> Iterator[sqlite3.Connection]:
        with self._lock:
            conn = self._conn
            conn.execute("BEGIN IMMEDIATE")
            try:
                yield conn
                conn.commit()
            except Exception:
                conn.rollback()
                raise

    def get_or_create_agent(self, agent: Dict[str, str]) -> Dict[str, str]:
        now = _utcnow()
        with self.transaction() as conn:
            conn.execute(
                """
                INSERT INTO agents (
                    agent_id, device_id, device_name, hostname, created_at, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(agent_id) DO UPDATE SET
                    device_id = excluded.device_id,
                    device_name = excluded.device_name,
                    hostname = excluded.hostname,
                    updated_at = excluded.updated_at
                """,
                (
                    agent["agent_id"],
                    agent["device_id"],
                    agent["device_name"],
                    agent["hostname"],
                    now,
                    now,
                ),
            )
        return agent

    def upsert_stream(
        self,
        *,
        agent_id: str,
        bucket_id: str,
        bucket_type: str,
        bucket_metadata: Dict[str, Any],
    ) -> Dict[str, Any]:
        stream_id = f"{agent_id}:{bucket_id}"
        now = _utcnow()
        with self.transaction() as conn:
            current = conn.execute(
                "SELECT next_seq, last_acked_seq FROM streams WHERE stream_id = ?",
                (stream_id,),
            ).fetchone()
            next_seq = int(current["next_seq"]) if current else 1
            last_acked_seq = int(current["last_acked_seq"]) if current else 0
            conn.execute(
                """
                INSERT INTO streams (
                    stream_id,
                    agent_id,
                    bucket_id,
                    bucket_type,
                    device_id,
                    username,
                    session_id,
                    bucket_metadata_json,
                    next_seq,
                    last_acked_seq,
                    last_sync_attempt_at,
                    last_sync_success_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, NULL)
                ON CONFLICT(stream_id) DO UPDATE SET
                    bucket_type = excluded.bucket_type,
                    device_id = excluded.device_id,
                    username = excluded.username,
                    session_id = excluded.session_id,
                    bucket_metadata_json = excluded.bucket_metadata_json
                """,
                (
                    stream_id,
                    agent_id,
                    bucket_id,
                    bucket_type,
                    str(bucket_metadata.get("device_id", "")),
                    bucket_metadata.get("username"),
                    bucket_metadata.get("session_id"),
                    canonical_json(bucket_metadata),
                    next_seq,
                    last_acked_seq,
                ),
            )
            row = conn.execute(
                "SELECT * FROM streams WHERE stream_id = ?",
                (stream_id,),
            ).fetchone()
        assert row is not None
        return dict(row)

    def get_streams(self) -> List[Dict[str, Any]]:
        rows = self._conn.execute(
            "SELECT * FROM streams ORDER BY stream_id ASC"
        ).fetchall()
        streams = []
        for row in rows:
            stream = dict(row)
            stream["bucket_metadata"] = json.loads(stream.pop("bucket_metadata_json"))
            streams.append(stream)
        return streams

    def record_source_event_state(
        self,
        *,
        stream_id: str,
        source_event_id: int,
        source_event_version: int,
        event_checksum: str,
        last_emitted_seq: int,
        is_final: bool = False,
    ) -> None:
        now = _utcnow()
        with self.transaction() as conn:
            conn.execute(
                """
                INSERT INTO source_event_state (
                    stream_id,
                    source_event_id,
                    source_event_version,
                    event_checksum,
                    last_emitted_seq,
                    is_final,
                    first_seen_at,
                    last_seen_at
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(stream_id, source_event_id) DO UPDATE SET
                    source_event_version = excluded.source_event_version,
                    event_checksum = excluded.event_checksum,
                    last_emitted_seq = excluded.last_emitted_seq,
                    is_final = excluded.is_final,
                    last_seen_at = excluded.last_seen_at
                """,
                (
                    stream_id,
                    source_event_id,
                    source_event_version,
                    event_checksum,
                    last_emitted_seq,
                    int(is_final),
                    now,
                    now,
                ),
            )

    def enqueue_bucket_upsert(
        self,
        *,
        stream_id: str,
        bucket_id: str,
        bucket_type: str,
        bucket_metadata: Dict[str, Any],
    ) -> int:
        payload = {
            "bucket_id": bucket_id,
            "bucket_type": bucket_type,
            "bucket_metadata": bucket_metadata,
        }
        return self._enqueue_op(stream_id=stream_id, op_type="bucket_upsert", payload=payload)

    def enqueue_event_upsert(
        self,
        *,
        stream_id: str,
        source_event_id: int,
        source_event_version: int,
        timestamp: str,
        duration: float,
        data: Dict[str, Any],
    ) -> int:
        payload = {
            "source_event_id": source_event_id,
            "source_event_version": source_event_version,
            "timestamp": timestamp,
            "duration": float(duration),
            "data": data,
        }
        return self._enqueue_op(stream_id=stream_id, op_type="event_upsert", payload=payload)

    def _enqueue_op(self, *, stream_id: str, op_type: str, payload: Dict[str, Any]) -> int:
        now = _utcnow()
        payload_json = canonical_json(payload)
        with self.transaction() as conn:
            stream = conn.execute(
                "SELECT next_seq FROM streams WHERE stream_id = ?",
                (stream_id,),
            ).fetchone()
            if stream is None:
                raise ValueError(f"Unknown stream_id: {stream_id}")

            seq = int(stream["next_seq"])
            conn.execute(
                """
                INSERT INTO outbox_ops (
                    stream_id,
                    seq,
                    op_type,
                    payload_json,
                    payload_checksum,
                    created_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                (
                    stream_id,
                    seq,
                    op_type,
                    payload_json,
                    canonical_json({"op_type": op_type, "payload": payload}),
                    now,
                ),
            )
            conn.execute(
                """
                UPDATE streams
                SET next_seq = ?
                WHERE stream_id = ?
                """,
                (seq + 1, stream_id),
            )
        return seq

    def list_unacked_ops(
        self,
        stream_id: str,
        *,
        after_seq: int = 0,
        limit: int = 500,
    ) -> List[Dict[str, Any]]:
        rows = self._conn.execute(
            """
            SELECT seq, op_type, payload_json
            FROM outbox_ops
            WHERE stream_id = ?
              AND acked_at IS NULL
              AND seq > ?
            ORDER BY seq ASC
            LIMIT ?
            """,
            (stream_id, after_seq, limit),
        ).fetchall()
        return [
            {
                "seq": int(row["seq"]),
                "op_type": str(row["op_type"]),
                "payload": json.loads(row["payload_json"]),
            }
            for row in rows
        ]

    def mark_acked(self, stream_id: str, acked_through_seq: int) -> int:
        now = _utcnow()
        with self.transaction() as conn:
            cursor = conn.execute(
                """
                UPDATE outbox_ops
                SET acked_at = COALESCE(acked_at, ?)
                WHERE stream_id = ?
                  AND seq <= ?
                """,
                (now, stream_id, acked_through_seq),
            )
            conn.execute(
                """
                UPDATE streams
                SET last_acked_seq = ?,
                    last_sync_success_at = ?
                WHERE stream_id = ?
                """,
                (acked_through_seq, now, stream_id),
            )
        return int(cursor.rowcount)

    def touch_sync_attempt(self, stream_id: str) -> None:
        now = _utcnow()
        with self.transaction() as conn:
            conn.execute(
                """
                UPDATE streams
                SET last_sync_attempt_at = ?
                WHERE stream_id = ?
                """,
                (now, stream_id),
            )
