"""Standalone market-data provider (TradingView WS primary + yfinance fallback).
No dependency on the desktop/backend code."""
from __future__ import annotations
import asyncio
import hashlib
import json
import logging
import random
import re
import string
from datetime import UTC, datetime

import pandas as pd
import websockets
import yfinance as yf

logger = logging.getLogger(__name__)

TV_URL = "wss://data.tradingview.com/socket.io/websocket"
TV_HEADERS = {"Origin": "https://www.tradingview.com",
              "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}

INDEX_TV = {"EGX30": "EGX:EGX30", "EGX70": "EGX:EGX70EWI", "EGX100": "EGX:EGX100EWI"}


def tv_symbol(ticker: str) -> str:
    t = ticker.strip().upper().removesuffix(".CA").removeprefix("EGX:")
    if t in INDEX_TV:
        return INDEX_TV[t]
    return f"EGX:{t}"


def yf_symbol(ticker: str) -> str:
    t = ticker.strip().upper().removesuffix(".CA").removeprefix("EGX:")
    return t if t in INDEX_TV else f"{t}.CA"


def _sid(prefix: str = "") -> str:
    return prefix + "".join(random.choices(string.ascii_lowercase + string.digits, k=12))


class TVConnector:
    def __init__(self, timeout: float = 20.0):
        self.timeout = timeout
        self.ws = None
        self._quotes: dict[str, asyncio.Future] = {}
        self._hist: dict[str, asyncio.Future] = {}
        self._task = None

    @staticmethod
    def _fmt(payload) -> str:
        enc = json.dumps(payload, separators=(",", ":"))
        return f"~m~{len(enc)}~m~{enc}"

    @staticmethod
    def _parse(data: str):
        msgs = []
        cur, mark = 0, "~m~"
        while True:
            s = data.find(mark, cur)
            if s < 0:
                break
            ls = s + len(mark)
            le = data.find(mark, ls)
            if le < 0:
                break
            try:
                ln = int(data[ls:le])
            except ValueError:
                cur = le + len(mark)
                continue
            ps = le + len(mark)
            payload = data[ps:ps + ln]
            cur = ps + ln
            if payload.startswith("~h~"):
                continue
            try:
                dec = json.loads(payload)
            except json.JSONDecodeError:
                continue
            if isinstance(dec, dict):
                msgs.append(dec)
        return msgs

    async def connect(self):
        if self.ws is not None:
            return
        self.ws = await websockets.connect(
            TV_URL, origin=TV_HEADERS["Origin"],
            additional_headers={"User-Agent": TV_HEADERS["User-Agent"]},
            open_timeout=self.timeout, close_timeout=5, ping_interval=20, ping_timeout=20)
        await self.ws.send(self._fmt({"m": "set_auth_token", "p": ["unauthorized_user_token"]}))
        self._task = asyncio.create_task(self._loop())

    async def _loop(self):
        try:
            async for raw in self.ws:
                r = raw.decode() if isinstance(raw, bytes) else raw
                if r.startswith("~h~"):
                    await self.ws.send(r)
                    continue
                for m in self._parse(r):
                    await self._dispatch(m)
        except asyncio.CancelledError:
            raise
        except Exception as e:
            logger.warning("TV loop: %s", e)

    async def _dispatch(self, m: dict):
        method, params = m.get("m"), m.get("p")
        if method == "timescale_update" and isinstance(params, list) and len(params) >= 2:
            cs, smap = str(params[0]), params[1]
            if isinstance(smap, dict):
                for series, sd in smap.items():
                    if isinstance(sd, dict) and isinstance(sd.get("s"), list):
                        fut = self._hist.pop(f"{cs}_{series}", None)
                        if fut is not None and not fut.done():
                            fut.set_result(sd["s"])

    @staticmethod
    def _norm(points) -> list:
        out, seen = {}, {}
        import numpy as _np
        for pt in points:
            v = pt.get("v") if isinstance(pt, dict) else None
            if not isinstance(v, list) or len(v) < 5:
                continue
            try:
                ts = int(float(v[0]))
                o, h, l, c = float(v[1]), float(v[2]), float(v[3]), float(v[4])
                vol = float(v[5]) if len(v) > 5 and v[5] is not None else 0.0
            except (TypeError, ValueError):
                continue
            if min(o, h, l, c) <= 0 or h < max(o, l, c) or l > min(o, h, c):
                continue
            seen[ts] = {"timestamp": ts, "open": o, "high": h, "low": l,
                        "close": c, "volume": max(vol, 0.0)}
        return [seen[k] for k in sorted(seen)]

    def _iv(self, interval: str) -> str:
        return {"1m": "1", "5m": "5", "15m": "15", "30m": "30", "1h": "60",
                "2h": "120", "4h": "240", "1d": "1D", "1wk": "1W", "1mo": "1M"}[interval.strip().lower()]

    def _count(self, period: str, interval: str) -> int:
        p, i = period.strip().lower(), interval.strip().lower()
        if i == "1d":
            return {"1mo": 40, "3mo": 90, "6mo": 180, "1y": 300, "2y": 550,
                    "5y": 1400, "10y": 2800, "max": 5000}.get(p, 300)
        return 1000

    async def history(self, symbol: str, period="5y", interval="1d", timeout=20.0):
        await self.connect()
        cs, series = _sid("cs_"), "s1"
        fut = asyncio.get_running_loop().create_future()
        self._hist[f"{cs}_{series}"] = fut
        await self.ws.send(self._fmt({"m": "chart_create_session", "p": [cs, ""]}))
        res = json.dumps({"symbol": symbol, "adjustment": "splits"}, separators=(",", ":"))
        await self.ws.send(self._fmt({"m": "resolve_symbol", "p": [cs, "symbol_1", f"={res}"]}))
        await self.ws.send(self._fmt({"m": "create_series", "p": [cs, series, series, "symbol_1",
                                                                  self._iv(interval),
                                                                  self._count(period, interval)]}))
        try:
            raw = await asyncio.wait_for(fut, timeout=timeout)
        finally:
            self._hist.pop(f"{cs}_{series}", None)
        return self._norm(raw)

    async def close(self):
        if self._task:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass
        if self.ws:
            await self.ws.close()
            self.ws = None


def _normalize_frame(frame: pd.DataFrame):
    if frame is None or frame.empty:
        return []
    df = frame.copy()
    df.columns = [str(c).strip().lower().replace(" ", "_") for c in df.columns]
    if any(c not in df.columns for c in ["open", "high", "low", "close", "volume"]):
        return []
    ts = pd.to_datetime(df.index, errors="coerce", utc=True)
    df = df.assign(timestamp=ts)
    for c in ["open", "high", "low", "close", "volume"]:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    df = df.dropna(subset=["timestamp", "open", "high", "low", "close"])
    df["volume"] = df["volume"].fillna(0).clip(lower=0)
    df = df.sort_values("timestamp").drop_duplicates("timestamp", keep="last")
    out = []
    for r in df.itertuples(index=False):
        o, h, l, c = float(r.open), float(r.high), float(r.low), float(r.close)
        if min(o, h, l, c) <= 0 or h < max(o, l, c) or l > min(o, h, c):
            continue
        out.append({"timestamp": r.timestamp.to_pydatetime().isoformat(), "open": round(o, 6),
                    "high": round(h, 6), "low": round(l, 6), "close": round(c, 6),
                    "volume": round(float(r.volume), 2)})
    return out


def _fp(candles) -> str:
    return hashlib.sha256(json.dumps(candles, sort_keys=True, separators=(",", ":"),
                                     ensure_ascii=True).encode()).hexdigest()


async def get_history(ticker: str, period="5y", interval="1d", timeout=20.0):
    sym = tv_symbol(ticker)
    tv = TVConnector(timeout=timeout)
    try:
        raw = await tv.history(sym, period, interval, timeout)
    except Exception as e:
        logger.warning("TV failed %s: %s", sym, e)
        raw = []
    finally:
        await tv.close()
    if raw:
        norm = [{"timestamp": datetime.fromtimestamp(c["timestamp"], tz=UTC).isoformat(),
                 "open": round(c["open"], 6), "high": round(c["high"], 6),
                 "low": round(c["low"], 6), "close": round(c["close"], 6),
                 "volume": round(c["volume"], 2)} for c in raw]
        return {"ticker": ticker, "provider": "tradingview", "candles": norm,
                "fingerprint": _fp(norm)}
    def dl():
        return yf.Ticker(yf_symbol(ticker)).history(period=period, interval=interval,
                                                    auto_adjust=False, actions=False,
                                                    timeout=timeout, raise_errors=True)
    frame = await asyncio.to_thread(dl)
    norm = _normalize_frame(frame)
    if not norm:
        raise RuntimeError(f"no data for {ticker}")
    return {"ticker": ticker, "provider": "yfinance", "candles": norm,
            "fingerprint": _fp(norm)}
