"""
AgentKVT Browser Agent — vision-driven, goal-seeking browser automation.

This is the v1 stub. It exposes the HTTP surface that the Mac runner's
`browser_agent` tool talks to, and walks each session through deterministic
canned state transitions so the rest of the system can be developed against
a stable contract before browser-use is wired in.

Replace `_advance_state` with the real browser-use loop in step 3.
"""

from __future__ import annotations

import logging
import os
import uuid
from datetime import datetime, timezone
from enum import Enum
from threading import Lock
from typing import Any, Optional

from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

logger = logging.getLogger("agentkvt.browseragent")
logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"))


class SessionStatus(str, Enum):
    pending = "pending"
    running = "running"
    awaiting_review = "awaiting_review"
    completed = "completed"
    failed = "failed"
    cancelled = "cancelled"


class CheckpointPolicy(str, Enum):
    before_submit = "before_submit"
    every_step = "every_step"
    never = "never"


class CreateSessionRequest(BaseModel):
    goal: str = Field(..., description="Plain-language goal, e.g. 'Register Everett for Camp Towhee session 2'.")
    start_url: str
    profile: dict[str, Any] = Field(default_factory=dict, description="Structured registration data (e.g. ChildProfile payload).")
    checkpoint_policy: CheckpointPolicy = CheckpointPolicy.before_submit
    model: Optional[str] = Field(default=None, description="Override vision model. Defaults to env BROWSER_AGENT_MODEL.")


class CreateSessionResponse(BaseModel):
    session_id: str
    status: SessionStatus


class ActionLogEntry(BaseModel):
    timestamp: str
    kind: str
    summary: str
    screenshot_path: Optional[str] = None


class SessionView(BaseModel):
    session_id: str
    status: SessionStatus
    goal: str
    start_url: str
    latest_screenshot_path: Optional[str] = None
    action_log: list[ActionLogEntry] = Field(default_factory=list)
    result: Optional[dict[str, Any]] = None
    error: Optional[str] = None


class DecisionRequest(BaseModel):
    decision: str = Field(..., description="approve | reject | edit")
    edits: Optional[dict[str, Any]] = None


class _Session:
    def __init__(self, req: CreateSessionRequest):
        self.id = str(uuid.uuid4())
        self.goal = req.goal
        self.start_url = req.start_url
        self.profile = req.profile
        self.checkpoint_policy = req.checkpoint_policy
        self.status = SessionStatus.pending
        self.action_log: list[ActionLogEntry] = []
        self.latest_screenshot_path: Optional[str] = None
        self.result: Optional[dict[str, Any]] = None
        self.error: Optional[str] = None

    def view(self) -> SessionView:
        return SessionView(
            session_id=self.id,
            status=self.status,
            goal=self.goal,
            start_url=self.start_url,
            latest_screenshot_path=self.latest_screenshot_path,
            action_log=list(self.action_log),
            result=self.result,
            error=self.error,
        )


_SESSIONS: dict[str, _Session] = {}
_LOCK = Lock()


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _log(session: _Session, kind: str, summary: str, screenshot_path: Optional[str] = None) -> None:
    session.action_log.append(
        ActionLogEntry(
            timestamp=_now(),
            kind=kind,
            summary=summary,
            screenshot_path=screenshot_path,
        )
    )
    if screenshot_path:
        session.latest_screenshot_path = screenshot_path


def _advance_state(session: _Session) -> None:
    """Drive the canned state machine forward on each GET.

    Replace this whole function with the real browser-use loop in step 3.
    """
    if session.status == SessionStatus.pending:
        session.status = SessionStatus.running
        _log(session, "navigate", f"Opened {session.start_url}")
        return

    if session.status == SessionStatus.running:
        _log(session, "fill", f"Filled registration fields from profile keys: {sorted(session.profile.keys())}")
        _log(session, "screenshot", "Captured filled-form preview", screenshot_path=f"/tmp/agentkvt-browseragent/{session.id}-preview.png")
        session.status = SessionStatus.awaiting_review
        return

    # awaiting_review, completed, failed, cancelled — no auto-advance.


app = FastAPI(title="AgentKVT Browser Agent", version="0.1.0")


@app.get("/healthz")
def healthz() -> dict[str, Any]:
    return {"status": "ok", "sessions": len(_SESSIONS)}


@app.post("/sessions", response_model=CreateSessionResponse)
def create_session(req: CreateSessionRequest) -> CreateSessionResponse:
    session = _Session(req)
    with _LOCK:
        _SESSIONS[session.id] = session
    logger.info("Created session %s for goal: %s", session.id, session.goal)
    return CreateSessionResponse(session_id=session.id, status=session.status)


@app.get("/sessions/{session_id}", response_model=SessionView)
def get_session(session_id: str) -> SessionView:
    with _LOCK:
        session = _SESSIONS.get(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="session not found")
        _advance_state(session)
        return session.view()


@app.post("/sessions/{session_id}/decisions", response_model=SessionView)
def submit_decision(session_id: str, req: DecisionRequest) -> SessionView:
    with _LOCK:
        session = _SESSIONS.get(session_id)
        if not session:
            raise HTTPException(status_code=404, detail="session not found")
        if session.status != SessionStatus.awaiting_review:
            raise HTTPException(status_code=409, detail=f"session is not awaiting review (status: {session.status})")

        decision = req.decision.lower().strip()
        if decision == "approve":
            _log(session, "submit", "Human approved; submitted form")
            session.status = SessionStatus.completed
            session.result = {"submitted": True, "confirmation": "stub-confirmation-id"}
        elif decision == "reject":
            _log(session, "abort", "Human rejected; session cancelled")
            session.status = SessionStatus.cancelled
        elif decision == "edit":
            _log(session, "edit", f"Human edited fields: {sorted((req.edits or {}).keys())}")
            session.status = SessionStatus.running
        else:
            raise HTTPException(status_code=400, detail=f"unknown decision: {req.decision}")

        return session.view()


@app.delete("/sessions/{session_id}")
def delete_session(session_id: str) -> dict[str, str]:
    with _LOCK:
        session = _SESSIONS.pop(session_id, None)
    if not session:
        raise HTTPException(status_code=404, detail="session not found")
    return {"status": "deleted", "session_id": session_id}
