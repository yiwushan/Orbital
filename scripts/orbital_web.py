#!/usr/bin/env python3
"""
Orbital LAN web dashboard with optional login and burst refresh.

- Shows local and remote metrics.
- Optional auth (disabled by default).
- Entering the page can trigger fast mode polling:
  5s interval for 3 minutes (configurable by env).
"""

from __future__ import annotations

import copy
import html
import hmac
import json
import os
import secrets
import socket
import subprocess
import threading
import time
import urllib.parse
from dataclasses import dataclass, field
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Dict, List, Optional, Tuple

WEB_UI_VERSION = "web-20260407-rxfix1"


def env_text(key: str, default: str) -> str:
    value = os.getenv(key, "").strip()
    return value if value else default


def env_int(key: str, default: int, min_value: int, max_value: int) -> int:
    raw = os.getenv(key, "").strip()
    if not raw:
        return default
    try:
        parsed = int(raw)
    except ValueError:
        return default
    return max(min_value, min(max_value, parsed))


def env_bool(key: str, default: bool) -> bool:
    raw = os.getenv(key, "").strip().lower()
    if not raw:
        return default
    if raw in ("1", "true", "yes", "on"):
        return True
    if raw in ("0", "false", "no", "off"):
        return False
    return default


def clamp01(value: float) -> float:
    return max(0.0, min(1.0, value))


def now_ms() -> int:
    return int(time.time() * 1000.0)


def format_size(num_bytes: float) -> str:
    units = ["B", "KB", "MB", "GB", "TB"]
    size = float(max(0.0, num_bytes))
    idx = 0
    while size >= 1024.0 and idx < len(units) - 1:
        size /= 1024.0
        idx += 1
    if idx == 0:
        return f"{int(size)} {units[idx]}"
    return f"{size:.1f} {units[idx]}"


def format_rate(num_bytes_per_sec: float) -> str:
    return f"{format_size(num_bytes_per_sec)}/s"


def parse_meminfo() -> Dict[str, int]:
    result: Dict[str, int] = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as fp:
            for raw in fp:
                if ":" not in raw:
                    continue
                key, rest = raw.split(":", 1)
                value_text = rest.strip().split(" ", 1)[0]
                try:
                    value_kb = int(value_text)
                except ValueError:
                    continue
                result[key.strip()] = value_kb
    except OSError:
        pass
    return result


def parse_cpu_stat_lines(lines: List[str]) -> Tuple[List[int], List[int], List[float]]:
    totals: List[int] = []
    idles: List[int] = []
    usage: List[float] = []
    for raw in lines:
        line = raw.strip()
        if not line.startswith("cpu"):
            continue
        parts = line.split()
        if len(parts) < 5:
            continue
        numeric: List[int] = []
        valid = True
        for item in parts[1:]:
            try:
                numeric.append(int(item))
            except ValueError:
                valid = False
                break
        if not valid:
            continue
        total = sum(numeric)
        idle = numeric[3] + (numeric[4] if len(numeric) > 4 else 0)
        totals.append(total)
        idles.append(idle)
        usage.append(0.0)
    return totals, idles, usage


def append_history(items: List[Tuple[int, float]], ts_ms: int, value: float, limit: int, window_ms: int) -> None:
    items.append((ts_ms, value))
    if len(items) > limit:
        del items[0 : len(items) - limit]
    cutoff = ts_ms - window_ms
    while items and items[0][0] < cutoff:
        items.pop(0)


def histories_to_lists(items: List[Tuple[int, float]]) -> Tuple[List[float], List[int]]:
    values = [float(v) for (_, v) in items]
    ts = [int(t) for (t, _) in items]
    return values, ts


def group_core_usage(per_core: List[float], groups: int = 8) -> List[float]:
    n = len(per_core)
    if n <= 0:
        return [0.0] * groups
    grouped: List[float] = []
    for g in range(groups):
        start = (g * n) // groups
        end = ((g + 1) * n) // groups
        if end <= start:
            grouped.append(0.0)
            continue
        chunk = per_core[start:end]
        grouped.append(sum(chunk) / len(chunk))
    return grouped


def find_battery_path() -> Optional[str]:
    root = "/sys/class/power_supply"
    if not os.path.isdir(root):
        return None
    try:
        for name in sorted(os.listdir(root)):
            candidate = os.path.join(root, name)
            type_path = os.path.join(candidate, "type")
            try:
                with open(type_path, "r", encoding="utf-8") as fp:
                    typ = fp.read().strip()
            except OSError:
                continue
            if typ == "Battery":
                return candidate
    except OSError:
        return None
    return None


def read_text(path: str) -> str:
    try:
        with open(path, "r", encoding="utf-8") as fp:
            return fp.read().strip()
    except OSError:
        return ""


def read_int(path: str) -> Optional[int]:
    text = read_text(path)
    if not text:
        return None
    try:
        return int(text)
    except ValueError:
        return None


def read_cpu_temp() -> str:
    best: Optional[float] = None
    thermal_root = "/sys/class/thermal"
    if os.path.isdir(thermal_root):
        try:
            for name in os.listdir(thermal_root):
                if not name.startswith("thermal_zone"):
                    continue
                temp = read_int(os.path.join(thermal_root, name, "temp"))
                if temp is None:
                    continue
                value = temp / 1000.0 if temp > 1000 else float(temp)
                if value <= 0.0 or value > 150.0:
                    continue
                if best is None or value > best:
                    best = value
        except OSError:
            pass
    if best is None:
        return "--"
    return f"{best:.1f} °C"


def parse_proc_net_dev() -> Tuple[int, int]:
    rx_total = 0
    tx_total = 0
    try:
        with open("/proc/net/dev", "r", encoding="utf-8") as fp:
            for raw in fp:
                line = raw.strip()
                if ":" not in line:
                    continue
                iface, rest = line.split(":", 1)
                iface = iface.strip()
                if iface == "lo":
                    continue
                cols = rest.split()
                if len(cols) < 16:
                    continue
                try:
                    rx_total += int(cols[0])
                    tx_total += int(cols[8])
                except ValueError:
                    continue
    except OSError:
        pass
    return rx_total, tx_total


def parse_df_root() -> Tuple[float, str]:
    try:
        st = os.statvfs("/")
    except OSError:
        return 0.0, "--"
    total = float(st.f_frsize) * float(st.f_blocks)
    avail = float(st.f_frsize) * float(st.f_bavail)
    if total <= 0:
        return 0.0, "--"
    used = max(0.0, total - avail)
    return used / total, f"{format_size(used)} / {format_size(total)}"


def parse_df_all_local() -> List[Dict[str, object]]:
    ignored_types = {
        "tmpfs",
        "devtmpfs",
        "proc",
        "sysfs",
        "cgroup",
        "cgroup2",
        "debugfs",
        "tracefs",
        "devpts",
        "mqueue",
        "autofs",
        "configfs",
        "fusectl",
        "pstore",
        "bpf",
        "efivarfs",
        "securityfs",
        "hugetlbfs",
        "rpc_pipefs",
        "overlay",
        "squashfs",
    }
    partitions: List[Dict[str, object]] = []
    cmd = ["df", "-B1", "-T"]
    try:
        proc = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2.0,
            check=False,
        )
    except Exception:  # pylint: disable=broad-except
        return partitions

    if proc.returncode != 0:
        return partitions

    for raw in proc.stdout.splitlines():
        line = raw.strip()
        if not line or line.startswith("Filesystem"):
            continue
        parts = line.split()
        if len(parts) < 7:
            continue
        fs_type = parts[1]
        if fs_type in ignored_types:
            continue
        try:
            total_b = int(parts[2])
            used_b = int(parts[3])
            avail_b = int(parts[4])
        except ValueError:
            continue
        if total_b <= 0:
            continue
        mount_point = " ".join(parts[6:])
        if not mount_point:
            continue
        partitions.append(
            {
                "filesystem": parts[0],
                "type": fs_type,
                "size": format_size(total_b),
                "used": format_size(used_b),
                "available": format_size(avail_b),
                "percent": float(used_b) / float(total_b),
                "mount": mount_point,
            }
        )
    return partitions


def parse_remote_output(
    output: str,
    prev_totals: List[int],
    prev_idles: List[int],
    has_prev: bool,
    ts_ms: int,
) -> Tuple[Dict[str, object], List[int], List[int], bool]:
    sections = {
        "cpu": [],
        "mem": [],
        "df_root": [],
        "df_all": [],
        "load": [],
    }
    section = "cpu"
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        if line == "__ORBITAL_MEM__":
            section = "mem"
            continue
        if line == "__ORBITAL_DF_ROOT__":
            section = "df_root"
            continue
        if line == "__ORBITAL_DF_ALL__":
            section = "df_all"
            continue
        if line == "__ORBITAL_LOAD__":
            section = "load"
            continue
        sections[section].append(line)

    cpu_lines = [line for line in sections["cpu"] if line.startswith("cpu")]
    totals: List[int] = []
    idles: List[int] = []
    usage: List[float] = []

    for line in cpu_lines:
        parts = line.split()
        if len(parts) < 5:
            continue
        try:
            values = [int(v) for v in parts[1:]]
        except ValueError:
            continue
        total = sum(values)
        idle = values[3] + (values[4] if len(values) > 4 else 0)
        idx = len(totals)
        totals.append(total)
        idles.append(idle)
        u = 0.0
        if has_prev and idx < len(prev_totals) and idx < len(prev_idles):
            diff_total = max(0, total - prev_totals[idx])
            diff_idle = max(0, idle - prev_idles[idx])
            if diff_total > 0:
                u = float(diff_total - diff_idle) / float(diff_total)
        usage.append(clamp01(u))

    if len(usage) < 2:
        raise ValueError("No CPU data from remote host")

    mem_values: Dict[str, int] = {}
    for line in sections["mem"]:
        if ":" not in line:
            continue
        key, rest = line.split(":", 1)
        value_text = rest.strip().split(" ", 1)[0]
        try:
            value_kb = int(value_text)
        except ValueError:
            continue
        mem_values[key.strip()] = value_kb

    mem_total_kb = mem_values.get("MemTotal", 0)
    mem_avail_kb = mem_values.get("MemAvailable", 0)
    mem_free_kb = mem_values.get("MemFree", 0)
    buffers_kb = mem_values.get("Buffers", 0)
    cached_kb = mem_values.get("Cached", 0)
    swap_total_kb = mem_values.get("SwapTotal", 0)
    swap_free_kb = mem_values.get("SwapFree", 0)
    swap_used_kb = max(0, swap_total_kb - swap_free_kb)

    if mem_total_kb > 0:
        mem_used_kb = max(0, mem_total_kb - mem_avail_kb)
        mem_percent = float(mem_used_kb) / float(mem_total_kb)
        mem_detail = f"{mem_used_kb / 1024.0 / 1024.0:.1f} GB / {mem_total_kb / 1024.0 / 1024.0:.1f} GB"
        mem_info = {
            "Used": format_size(mem_used_kb * 1024.0),
            "Total": format_size(mem_total_kb * 1024.0),
            "Available": format_size(mem_avail_kb * 1024.0),
            "Free": format_size(mem_free_kb * 1024.0),
            "Cached": format_size(cached_kb * 1024.0),
            "Buffers": format_size(buffers_kb * 1024.0),
            "Swap Used": format_size(swap_used_kb * 1024.0),
            "Swap Free": format_size(swap_free_kb * 1024.0),
            "Swap Total": format_size(swap_total_kb * 1024.0),
        }
    else:
        mem_percent = 0.0
        mem_detail = "--"
        mem_info = {}

    disk_total = 0
    disk_used = 0
    partitions: List[Dict[str, object]] = []
    for line in sections["df_all"]:
        parts = line.split()
        if len(parts) < 7 or parts[0] == "Filesystem":
            continue
        try:
            total_b = int(parts[2])
            used_b = int(parts[3])
            avail_b = int(parts[4])
        except ValueError:
            continue
        if total_b <= 0:
            continue
        mount_point = " ".join(parts[6:])
        percent = float(used_b) / float(total_b)
        partitions.append(
            {
                "filesystem": parts[0],
                "type": parts[1],
                "size": format_size(total_b),
                "used": format_size(used_b),
                "available": format_size(avail_b),
                "percent": percent,
                "mount": mount_point,
            }
        )
        if mount_point == "/" and disk_total <= 0:
            disk_total = total_b
            disk_used = used_b

    for line in sections["df_root"]:
        parts = line.split()
        if len(parts) < 6 or parts[-1] != "/":
            continue
        try:
            disk_total = int(parts[1])
            disk_used = int(parts[2])
        except ValueError:
            pass
        break

    if disk_total > 0:
        disk_percent = float(disk_used) / float(disk_total)
        disk_detail = f"{format_size(disk_used)} / {format_size(disk_total)}"
    else:
        disk_percent = 0.0
        disk_detail = "--"

    load_avg = "--"
    if sections["load"]:
        parts = sections["load"][0].split()
        if len(parts) >= 3:
            load_avg = f"{parts[0]} / {parts[1]} / {parts[2]}"

    per_core = usage[1:]
    payload = {
        "tsMs": ts_ms,
        "coreCount": len(per_core),
        "cpuTotal": usage[0],
        "cpuGroups": group_core_usage(per_core, 8),
        "memPercent": clamp01(mem_percent),
        "memDetail": mem_detail,
        "memInfo": mem_info,
        "diskPercent": clamp01(disk_percent),
        "diskDetail": disk_detail,
        "diskPartitions": partitions,
        "loadAvg": load_avg,
    }
    return payload, totals, idles, True


@dataclass
class RemoteHostState:
    name: str
    host: str
    port: int
    status: str = "Not Configured"
    error: str = ""
    busy: bool = False
    core_count: int = 0
    cpu_total: float = 0.0
    cpu_groups: List[float] = field(default_factory=lambda: [0.0] * 8)
    mem_percent: float = 0.0
    mem_detail: str = "--"
    mem_info: Dict[str, str] = field(default_factory=dict)
    disk_percent: float = 0.0
    disk_detail: str = "--"
    disk_partitions: List[Dict[str, object]] = field(default_factory=list)
    load_avg: str = "--"
    last_update_ms: int = 0
    prev_cpu_totals: List[int] = field(default_factory=list)
    prev_cpu_idles: List[int] = field(default_factory=list)
    has_prev_cpu: bool = False
    cpu_history: List[Tuple[int, float]] = field(default_factory=list)
    mem_history: List[Tuple[int, float]] = field(default_factory=list)
    disk_history: List[Tuple[int, float]] = field(default_factory=list)


class OrbitalSampler:
    REMOTE_COLLECT_COMMAND = (
        "LC_ALL=C sh -c '"
        "cat /proc/stat; "
        "echo __ORBITAL_MEM__; "
        "cat /proc/meminfo; "
        "echo __ORBITAL_DF_ROOT__; "
        "df -B1 /; "
        "echo __ORBITAL_DF_ALL__; "
        "df -B1 -T; "
        "echo __ORBITAL_LOAD__; "
        "cat /proc/loadavg'"
    )

    def __init__(self) -> None:
        self.lock = threading.RLock()
        self.stop_event = threading.Event()
        self.polling = False
        self.last_poll_ts = 0.0
        self.fast_until_ts = 0.0

        self.auth_enabled = env_bool("ORBITAL_WEB_AUTH_ENABLED", False)
        self.show_remote_addr = env_bool("ORBITAL_WEB_SHOW_REMOTE_ADDR", False)
        self.username = env_text("ORBITAL_WEB_USER", "admin")
        self.password = env_text("ORBITAL_WEB_PASSWORD", "orbital123")
        self.session_hours = env_int("ORBITAL_WEB_SESSION_HOURS", 8, 1, 72)

        self.base_interval_sec = env_int("ORBITAL_WEB_BASE_INTERVAL_SEC", 60, 10, 3600)
        self.burst_interval_sec = env_int("ORBITAL_WEB_BURST_INTERVAL_SEC", 5, 1, 120)
        self.burst_duration_sec = env_int("ORBITAL_WEB_BURST_DURATION_SEC", 180, 30, 1800)
        self.remote_timeout_sec = env_int("ORBITAL_WEB_REMOTE_TIMEOUT_SEC", 7, 3, 30)
        self.history_limit = env_int("ORBITAL_WEB_HISTORY_LIMIT", 800, 60, 4000)
        self.history_window_ms = env_int("ORBITAL_WEB_HISTORY_WINDOW_SEC", 3600, 300, 14400) * 1000

        self._battery_path = find_battery_path()

        self._local_prev_cpu_totals: List[int] = []
        self._local_prev_cpu_idles: List[int] = []
        self._local_has_prev_cpu = False
        self._local_prev_net_rx = 0
        self._local_prev_net_tx = 0
        self._local_prev_net_ts = 0.0
        self._local_cpu_history: List[Tuple[int, float]] = []
        self._local_mem_history: List[Tuple[int, float]] = []
        self._local_net_rx_history: List[Tuple[int, float]] = []
        self._local_net_tx_history: List[Tuple[int, float]] = []

        self._hosts: List[RemoteHostState] = []
        self._load_remote_hosts()

        self._sessions: Dict[str, float] = {}
        self._snapshot: Dict[str, object] = self._empty_snapshot()
        self._thread = threading.Thread(target=self._poll_loop, name="orbital-web-poll", daemon=True)

    def _empty_snapshot(self) -> Dict[str, object]:
        return {
            "timestampMs": now_ms(),
            "pollIntervalSec": self.base_interval_sec,
            "burstActive": False,
            "burstRemainingSec": 0,
            "local": {},
            "remoteServers": [],
        }

    def _load_remote_hosts(self) -> None:
        self._hosts.clear()
        for i in range(2):
            slot = i + 1
            name = env_text(f"ORBITAL_REMOTE_NAME_{slot}", f"Remote-{chr(ord('A') + i)}")
            host = env_text(f"ORBITAL_REMOTE_HOST_{slot}", "")
            port = env_int(f"ORBITAL_REMOTE_PORT_{slot}", 22, 1, 65535)
            state = RemoteHostState(name=name, host=host, port=port)
            if host:
                state.status = "Pending"
            else:
                state.status = "Not Configured"
                state.error = f"Set ORBITAL_REMOTE_HOST_{slot}"
            self._hosts.append(state)

    def start(self) -> None:
        self.poll_if_due(force=True)
        self._thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        if self._thread.is_alive():
            self._thread.join(timeout=2.0)

    def _poll_loop(self) -> None:
        while not self.stop_event.wait(1.0):
            self.poll_if_due(force=False)
            self._cleanup_sessions()

    def _current_interval_locked(self, now_ts: float) -> int:
        if now_ts < self.fast_until_ts:
            return self.burst_interval_sec
        return self.base_interval_sec

    def trigger_burst(self) -> None:
        with self.lock:
            deadline = time.time() + float(self.burst_duration_sec)
            if deadline > self.fast_until_ts:
                self.fast_until_ts = deadline
        self.poll_if_due(force=True)

    def authenticate(self, username: str, password: str) -> bool:
        if not self.auth_enabled:
            return True
        return hmac.compare_digest(username, self.username) and hmac.compare_digest(password, self.password)

    def create_session(self) -> str:
        if not self.auth_enabled:
            return "no-auth"
        token = secrets.token_urlsafe(32)
        expires_ts = time.time() + float(self.session_hours * 3600)
        with self.lock:
            self._sessions[token] = expires_ts
        return token

    def validate_session(self, token: str) -> bool:
        if not self.auth_enabled:
            return True
        if not token:
            return False
        now_ts = time.time()
        with self.lock:
            expires = self._sessions.get(token)
            if expires is None:
                return False
            if expires < now_ts:
                self._sessions.pop(token, None)
                return False
            return True

    def clear_session(self, token: str) -> None:
        if not self.auth_enabled:
            return
        if not token:
            return
        with self.lock:
            self._sessions.pop(token, None)

    def _cleanup_sessions(self) -> None:
        if not self.auth_enabled:
            return
        now_ts = time.time()
        with self.lock:
            stale = [k for (k, exp) in self._sessions.items() if exp < now_ts]
            for token in stale:
                self._sessions.pop(token, None)

    def poll_if_due(self, force: bool) -> bool:
        with self.lock:
            now_ts = time.time()
            interval_sec = self._current_interval_locked(now_ts)
            due = force or (self.last_poll_ts <= 0.0) or ((now_ts - self.last_poll_ts) >= float(interval_sec))
            if not due or self.polling:
                return False
            self.polling = True

        snapshot = self._collect_snapshot()

        with self.lock:
            self._snapshot = snapshot
            self.last_poll_ts = time.time()
            self.polling = False
        return True

    def snapshot(self) -> Dict[str, object]:
        with self.lock:
            now_ts = time.time()
            burst_active = now_ts < self.fast_until_ts
            burst_remaining = max(0, int(self.fast_until_ts - now_ts)) if burst_active else 0
            snapshot = copy.deepcopy(self._snapshot)
            snapshot["pollIntervalSec"] = self._current_interval_locked(now_ts)
            snapshot["burstActive"] = burst_active
            snapshot["burstRemainingSec"] = burst_remaining
            return snapshot

    def _collect_snapshot(self) -> Dict[str, object]:
        ts_ms = now_ms()
        local = self._collect_local(ts_ms)
        remote = self._collect_remote(ts_ms)
        with self.lock:
            interval_sec = self._current_interval_locked(time.time())
            burst_active = time.time() < self.fast_until_ts
            burst_remaining = max(0, int(self.fast_until_ts - time.time())) if burst_active else 0
        return {
            "timestampMs": ts_ms,
            "pollIntervalSec": interval_sec,
            "burstActive": burst_active,
            "burstRemainingSec": burst_remaining,
            "local": local,
            "remoteServers": remote,
        }

    def _collect_local(self, ts_ms: int) -> Dict[str, object]:
        cpu_totals: List[int] = []
        cpu_idles: List[int] = []
        cpu_usage: List[float] = []
        try:
            with open("/proc/stat", "r", encoding="utf-8") as fp:
                for raw in fp:
                    line = raw.strip()
                    if not line.startswith("cpu"):
                        break
                    parts = line.split()
                    if len(parts) < 5:
                        continue
                    try:
                        vals = [int(v) for v in parts[1:]]
                    except ValueError:
                        continue
                    total = sum(vals)
                    idle = vals[3] + (vals[4] if len(vals) > 4 else 0)
                    idx = len(cpu_totals)
                    usage = 0.0
                    if (
                        self._local_has_prev_cpu
                        and idx < len(self._local_prev_cpu_totals)
                        and idx < len(self._local_prev_cpu_idles)
                    ):
                        diff_total = max(0, total - self._local_prev_cpu_totals[idx])
                        diff_idle = max(0, idle - self._local_prev_cpu_idles[idx])
                        if diff_total > 0:
                            usage = float(diff_total - diff_idle) / float(diff_total)
                    cpu_totals.append(total)
                    cpu_idles.append(idle)
                    cpu_usage.append(clamp01(usage))
        except OSError:
            pass

        if cpu_usage:
            cpu_total = cpu_usage[0]
            cpu_cores = cpu_usage[1:]
        else:
            cpu_total = 0.0
            cpu_cores = []

        self._local_prev_cpu_totals = cpu_totals
        self._local_prev_cpu_idles = cpu_idles
        self._local_has_prev_cpu = bool(cpu_totals)

        mem = parse_meminfo()
        mem_total_kb = mem.get("MemTotal", 0)
        mem_avail_kb = mem.get("MemAvailable", 0)
        mem_free_kb = mem.get("MemFree", 0)
        cached_kb = mem.get("Cached", 0)
        buffers_kb = mem.get("Buffers", 0)
        swap_total_kb = mem.get("SwapTotal", 0)
        swap_free_kb = mem.get("SwapFree", 0)
        swap_used_kb = max(0, swap_total_kb - swap_free_kb)

        if mem_total_kb > 0:
            mem_used_kb = max(0, mem_total_kb - mem_avail_kb)
            mem_percent = float(mem_used_kb) / float(mem_total_kb)
            mem_detail = f"{mem_used_kb / 1024.0 / 1024.0:.1f} / {mem_total_kb / 1024.0 / 1024.0:.1f} GB"
            mem_info = {
                "Used": format_size(mem_used_kb * 1024.0),
                "Total": format_size(mem_total_kb * 1024.0),
                "Available": format_size(mem_avail_kb * 1024.0),
                "Free": format_size(mem_free_kb * 1024.0),
                "Cached": format_size(cached_kb * 1024.0),
                "Buffers": format_size(buffers_kb * 1024.0),
                "Swap Used": format_size(swap_used_kb * 1024.0),
                "Swap Free": format_size(swap_free_kb * 1024.0),
                "Swap Total": format_size(swap_total_kb * 1024.0),
            }
        else:
            mem_percent = 0.0
            mem_detail = "--"
            mem_info = {}

        disk_percent, disk_root_usage = parse_df_root()
        disk_partitions = parse_df_all_local()

        bat_percent = 0
        bat_state = "Unknown"
        bat_details: Dict[str, object] = {}
        if self._battery_path:
            cap = read_int(os.path.join(self._battery_path, "capacity"))
            st = read_text(os.path.join(self._battery_path, "status"))
            if cap is not None:
                bat_percent = max(0, min(100, cap))
            if st:
                bat_state = st
            voltage = read_int(os.path.join(self._battery_path, "voltage_now"))
            current = read_int(os.path.join(self._battery_path, "current_now"))
            temp = read_int(os.path.join(self._battery_path, "temp"))
            if voltage is not None:
                bat_details["Voltage"] = f"{voltage / 1_000_000.0:.2f} V"
            if current is not None:
                bat_details["Current"] = f"{current / 1_000_000.0:.2f} A"
            if temp is not None:
                bat_details["Temp"] = f"{temp / 10.0:.1f} °C"

        rx_total, tx_total = parse_proc_net_dev()
        now_ts = time.time()
        rx_rate = 0.0
        tx_rate = 0.0
        if self._local_prev_net_ts > 0.0 and now_ts > self._local_prev_net_ts:
            dt = now_ts - self._local_prev_net_ts
            if dt > 0.0:
                rx_rate = max(0.0, float(rx_total - self._local_prev_net_rx) / dt)
                tx_rate = max(0.0, float(tx_total - self._local_prev_net_tx) / dt)
        self._local_prev_net_rx = rx_total
        self._local_prev_net_tx = tx_total
        self._local_prev_net_ts = now_ts

        append_history(self._local_cpu_history, ts_ms, cpu_total * 100.0, self.history_limit, self.history_window_ms)
        append_history(self._local_mem_history, ts_ms, mem_percent * 100.0, self.history_limit, self.history_window_ms)
        append_history(self._local_net_rx_history, ts_ms, rx_rate, self.history_limit, self.history_window_ms)
        append_history(self._local_net_tx_history, ts_ms, tx_rate, self.history_limit, self.history_window_ms)

        cpu_hist, cpu_hist_ts = histories_to_lists(self._local_cpu_history)
        mem_hist, mem_hist_ts = histories_to_lists(self._local_mem_history)
        rx_hist, rx_hist_ts = histories_to_lists(self._local_net_rx_history)
        tx_hist, tx_hist_ts = histories_to_lists(self._local_net_tx_history)

        try:
            load_avg = os.getloadavg()
            load_text = f"{load_avg[0]:.2f} / {load_avg[1]:.2f} / {load_avg[2]:.2f}"
        except OSError:
            load_text = "--"

        return {
            "cpuTotal": cpu_total,
            "cpuCores": cpu_cores,
            "cpuTemp": read_cpu_temp(),
            "cpuHistory": cpu_hist,
            "cpuHistoryTs": cpu_hist_ts,
            "memPercent": mem_percent,
            "memDetail": mem_detail,
            "memInfo": mem_info,
            "memHistory": mem_hist,
            "memHistoryTs": mem_hist_ts,
            "diskPercent": disk_percent,
            "diskRootUsage": disk_root_usage,
            "diskPartitions": disk_partitions,
            "batPercent": bat_percent,
            "batState": bat_state,
            "batDetails": bat_details,
            "netRxSpeed": format_rate(rx_rate),
            "netTxSpeed": format_rate(tx_rate),
            "netRxHistory": rx_hist,
            "netRxHistoryTs": rx_hist_ts,
            "netTxHistory": tx_hist,
            "netTxHistoryTs": tx_hist_ts,
            "loadAverage": load_text,
        }

    def _collect_remote(self, ts_ms: int) -> List[Dict[str, object]]:
        results: List[Dict[str, object]] = []
        for host in self._hosts:
            if not host.host:
                host.status = "Not Configured"
                host.error = host.error or "Missing host"
                results.append(self._host_to_map(host))
                continue

            cmd = [
                "ssh",
                "-o",
                "BatchMode=yes",
                "-o",
                "ConnectTimeout=4",
                "-o",
                "StrictHostKeyChecking=no",
                "-o",
                "UserKnownHostsFile=/dev/null",
                "-p",
                str(host.port),
                host.host,
                self.REMOTE_COLLECT_COMMAND,
            ]

            host.busy = True
            try:
                proc = subprocess.run(
                    cmd,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=self.remote_timeout_sec,
                    check=False,
                )
                if proc.returncode != 0:
                    err = (proc.stderr or proc.stdout or "").strip()
                    host.status = "Offline"
                    host.error = self._sanitize_remote_error(err, host.host)[:160] if err else f"ssh exit {proc.returncode}"
                else:
                    try:
                        payload, totals, idles, has_prev = parse_remote_output(
                            proc.stdout,
                            host.prev_cpu_totals,
                            host.prev_cpu_idles,
                            host.has_prev_cpu,
                            ts_ms,
                        )
                        host.status = "Online"
                        host.error = ""
                        host.core_count = int(payload["coreCount"])
                        host.cpu_total = float(payload["cpuTotal"])
                        host.cpu_groups = [float(v) for v in payload["cpuGroups"]]
                        host.mem_percent = float(payload["memPercent"])
                        host.mem_detail = str(payload["memDetail"])
                        host.mem_info = dict(payload["memInfo"])  # type: ignore[arg-type]
                        host.disk_percent = float(payload["diskPercent"])
                        host.disk_detail = str(payload["diskDetail"])
                        host.disk_partitions = list(payload["diskPartitions"])  # type: ignore[arg-type]
                        host.load_avg = str(payload["loadAvg"])
                        host.prev_cpu_totals = totals
                        host.prev_cpu_idles = idles
                        host.has_prev_cpu = has_prev
                        host.last_update_ms = ts_ms
                        append_history(host.cpu_history, ts_ms, host.cpu_total * 100.0, self.history_limit, self.history_window_ms)
                        append_history(host.mem_history, ts_ms, host.mem_percent * 100.0, self.history_limit, self.history_window_ms)
                        append_history(host.disk_history, ts_ms, host.disk_percent * 100.0, self.history_limit, self.history_window_ms)
                    except Exception as exc:  # pylint: disable=broad-except
                        host.status = "Offline"
                        host.error = self._sanitize_remote_error(str(exc), host.host)[:160]
            except subprocess.TimeoutExpired:
                host.status = "Offline"
                host.error = "ssh timeout"
            finally:
                host.busy = False

            results.append(self._host_to_map(host))
        return results

    def _sanitize_remote_error(self, text: str, host_text: str) -> str:
        sanitized = text or ""
        if not self.show_remote_addr:
            host_only = host_text
            if "@" in host_only:
                host_only = host_only.split("@", 1)[1]
            for marker in (host_text, host_only):
                marker = marker.strip()
                if marker:
                    sanitized = sanitized.replace(marker, "<hidden>")
        return sanitized

    def _host_to_map(self, host: RemoteHostState) -> Dict[str, object]:
        cpu_hist, cpu_hist_ts = histories_to_lists(host.cpu_history)
        mem_hist, mem_hist_ts = histories_to_lists(host.mem_history)
        disk_hist, disk_hist_ts = histories_to_lists(host.disk_history)
        last_update = "--"
        if host.last_update_ms > 0:
            last_update = time.strftime("%H:%M:%S", time.localtime(host.last_update_ms / 1000.0))
        result = {
            "name": host.name,
            "status": host.status,
            "error": host.error,
            "busy": host.busy,
            "coreCount": host.core_count,
            "cpuTotal": host.cpu_total,
            "cpuGroups": host.cpu_groups,
            "cpuHistory": cpu_hist,
            "cpuHistoryTs": cpu_hist_ts,
            "memPercent": host.mem_percent,
            "memDetail": host.mem_detail,
            "memInfo": host.mem_info,
            "memHistory": mem_hist,
            "memHistoryTs": mem_hist_ts,
            "diskPercent": host.disk_percent,
            "diskDetail": host.disk_detail,
            "diskPartitions": host.disk_partitions,
            "diskHistory": disk_hist,
            "diskHistoryTs": disk_hist_ts,
            "loadAvg": host.load_avg,
            "lastUpdate": last_update,
        }
        if self.show_remote_addr:
            result["host"] = host.host
            result["port"] = host.port
        return result


class OrbitalHandler(BaseHTTPRequestHandler):
    sampler: OrbitalSampler = None  # type: ignore[assignment]
    cookie_name = "orbital_session"

    def log_message(self, fmt: str, *args) -> None:  # pylint: disable=arguments-differ
        message = fmt % args
        print(f"[orbital_web] {self.address_string()} {self.command} {self.path} - {message}", flush=True)

    def do_GET(self) -> None:  # pylint: disable=invalid-name
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path

        if path == "/healthz":
            self._send_text(HTTPStatus.OK, "ok\n")
            return

        if path == "/api/snapshot":
            if not self._is_authenticated():
                self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
                return
            self.sampler.poll_if_due(force=False)
            payload = self.sampler.snapshot()
            self._send_json(HTTPStatus.OK, payload)
            return

        if path == "/login":
            if not self.sampler.auth_enabled:
                self._redirect("/")
                return
            if self._is_authenticated():
                self._redirect("/")
                return
            self._send_html(HTTPStatus.OK, self._login_page(error=""))
            return

        if path == "/":
            if not self._is_authenticated():
                self._redirect("/login")
                return
            if not self.sampler.auth_enabled:
                self.sampler.trigger_burst()
            self._send_html(HTTPStatus.OK, self._dashboard_page())
            return

        self._send_text(HTTPStatus.NOT_FOUND, "not found\n")

    def do_POST(self) -> None:  # pylint: disable=invalid-name
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path
        body = self._read_form()

        if path == "/login":
            if not self.sampler.auth_enabled:
                self.sampler.trigger_burst()
                self._redirect("/")
                return
            username = body.get("username", [""])[0]
            password = body.get("password", [""])[0]
            if self.sampler.authenticate(username, password):
                token = self.sampler.create_session()
                self.sampler.trigger_burst()
                self._redirect("/", set_cookie=token)
            else:
                self._send_html(HTTPStatus.UNAUTHORIZED, self._login_page(error="用户名或密码错误"))
            return

        if path == "/logout":
            token = self._session_token()
            if token:
                self.sampler.clear_session(token)
            if self.sampler.auth_enabled:
                self._redirect("/login", clear_cookie=True)
            else:
                self._redirect("/")
            return

        if path == "/api/burst":
            if not self._is_authenticated():
                self._send_json(HTTPStatus.UNAUTHORIZED, {"error": "unauthorized"})
                return
            self.sampler.trigger_burst()
            self._send_json(HTTPStatus.OK, {"ok": True})
            return

        self._send_text(HTTPStatus.NOT_FOUND, "not found\n")

    def _read_form(self) -> Dict[str, List[str]]:
        length_text = self.headers.get("Content-Length", "0")
        try:
            length = int(length_text)
        except ValueError:
            length = 0
        raw = self.rfile.read(max(0, length)) if length > 0 else b""
        data = raw.decode("utf-8", errors="ignore")
        return urllib.parse.parse_qs(data, keep_blank_values=True)

    def _cookie_map(self) -> Dict[str, str]:
        header = self.headers.get("Cookie", "")
        result: Dict[str, str] = {}
        for item in header.split(";"):
            if "=" not in item:
                continue
            key, value = item.split("=", 1)
            result[key.strip()] = value.strip()
        return result

    def _session_token(self) -> str:
        return self._cookie_map().get(self.cookie_name, "")

    def _is_authenticated(self) -> bool:
        if not self.sampler.auth_enabled:
            return True
        return self.sampler.validate_session(self._session_token())

    def _send_common_headers(self, status: HTTPStatus, content_type: str, extra_headers: Optional[List[str]] = None) -> None:
        self.send_response(status)
        self.send_header("Content-Type", content_type)
        self.send_header("Cache-Control", "no-store")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        if extra_headers:
            for header in extra_headers:
                key, value = header.split(":", 1)
                self.send_header(key.strip(), value.strip())
        self.end_headers()

    def _send_json(self, status: HTTPStatus, payload: Dict[str, object]) -> None:
        data = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
        self._send_common_headers(status, "application/json; charset=utf-8")
        self.wfile.write(data)

    def _send_text(self, status: HTTPStatus, text: str) -> None:
        data = text.encode("utf-8")
        self._send_common_headers(status, "text/plain; charset=utf-8")
        self.wfile.write(data)

    def _send_html(self, status: HTTPStatus, html_text: str) -> None:
        data = html_text.encode("utf-8")
        self._send_common_headers(status, "text/html; charset=utf-8")
        self.wfile.write(data)

    def _redirect(self, location: str, set_cookie: Optional[str] = None, clear_cookie: bool = False) -> None:
        headers: List[str] = [f"Location: {location}"]
        if set_cookie and self.sampler.auth_enabled:
            max_age = self.sampler.session_hours * 3600
            headers.append(
                f"Set-Cookie: {self.cookie_name}={set_cookie}; Path=/; HttpOnly; SameSite=Lax; Max-Age={max_age}"
            )
        if clear_cookie and self.sampler.auth_enabled:
            headers.append(
                f"Set-Cookie: {self.cookie_name}=deleted; Path=/; HttpOnly; SameSite=Lax; Max-Age=0"
            )
        self._send_common_headers(HTTPStatus.FOUND, "text/plain; charset=utf-8", headers)
        self.wfile.write(b"redirecting\n")

    def _login_page(self, error: str) -> str:
        error_html = ""
        if error:
            error_html = f"<div class='error'>{html.escape(error)}</div>"
        return f"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Orbital Web Login</title>
  <style>
    body {{ margin: 0; font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif; background: #10151c; color: #e6edf7; }}
    .wrap {{ min-height: 100vh; display: flex; align-items: center; justify-content: center; }}
    .card {{ width: min(92vw, 360px); background: #161d27; border: 1px solid #2c3a4f; border-radius: 14px; padding: 18px; }}
    h1 {{ margin: 0 0 14px 0; font-size: 20px; }}
    .hint {{ color: #9cb1cf; font-size: 12px; margin-bottom: 12px; }}
    label {{ display: block; font-size: 12px; margin-bottom: 6px; color: #b9c9dd; }}
    input {{ width: 100%; box-sizing: border-box; margin-bottom: 12px; padding: 10px; border-radius: 8px; border: 1px solid #2a3748; background: #0e131a; color: #edf4ff; }}
    button {{ width: 100%; padding: 10px; border: 0; border-radius: 8px; background: #2d8cff; color: white; font-weight: 600; cursor: pointer; }}
    .error {{ margin-bottom: 12px; color: #ff8888; font-size: 12px; }}
  </style>
</head>
<body>
  <div class="wrap">
    <form class="card" method="post" action="/login">
      <h1>Orbital 内网页面</h1>
      <div class="hint">登录后可查看本机与远端服务器状态；登录会触发 3 分钟 5 秒刷新。</div>
      {error_html}
      <label>用户名</label>
      <input name="username" autocomplete="username" required />
      <label>密码</label>
      <input type="password" name="password" autocomplete="current-password" required />
      <button type="submit">登录</button>
    </form>
  </div>
</body>
</html>"""

    def _dashboard_page(self) -> str:
        auth_button_html = '<form method="post" action="/logout"><button type="submit">退出</button></form>'
        if not self.sampler.auth_enabled:
            auth_button_html = ""

        page = """<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Orbital Dashboard Web</title>
  <style>
    :root { color-scheme: dark; --bg:#10151b; --panel:#171e28; --panel2:#1d2633; --line:#2f3d50; --text:#e6eef9; --muted:#9eb2cc; --ok:#69d39b; --bad:#ff8f8f; --cpu:#4fc3f7; --mem:#7e9bff; --netrx:#55efc4; --nettx:#ffb067; --disk:#ffd54f; }
    * { box-sizing: border-box; }
    body { margin: 0; background: radial-gradient(1200px 600px at 20% -10%, #1a2432 0%, var(--bg) 55%); color: var(--text); font-family: -apple-system, BlinkMacSystemFont, Segoe UI, Roboto, sans-serif; }
    .top { display:flex; align-items:center; justify-content:space-between; gap:10px; padding: 12px 14px; border-bottom:1px solid var(--line); background: rgba(13,18,24,0.7); backdrop-filter: blur(5px); position: sticky; top:0; z-index:10; }
    .title { font-size: 17px; font-weight: 700; letter-spacing: .2px; }
    .meta { margin-top: 2px; font-size: 12px; color: var(--muted); }
    .btns { display:flex; gap:8px; }
    button { border:1px solid #3a4d66; background:#223044; color:#dcebff; border-radius:8px; padding:8px 10px; cursor:pointer; font-size:12px; }
    .content { padding: 12px; display:grid; gap:12px; }
    .local-grid { display:grid; gap:10px; grid-template-columns: repeat(4, minmax(180px, 1fr)); }
    .card { background: linear-gradient(180deg, var(--panel2), var(--panel)); border:1px solid var(--line); border-radius: 12px; padding:10px; box-shadow: 0 6px 18px rgba(0,0,0,.18); }
    .card h3 { margin:0 0 8px 0; font-size:13px; color:#dfe9f8; font-weight:700; }
    .cpu-card { grid-column: span 2; }
    .net-card { grid-column: span 2; }
    .kv { display:flex; gap:8px; justify-content:space-between; align-items:center; margin-bottom:6px; }
    .label { color: var(--muted); font-size:12px; }
    .value { font-size:14px; font-weight:700; }
    .small { color: var(--muted); font-size:11px; }
    .core-bars { display:grid; grid-template-columns: repeat(8, 1fr); gap:4px; align-items:end; height:52px; margin: 2px 0 8px; }
    .core-bar { position:relative; background:#222d3b; border-radius:4px; overflow:hidden; border:1px solid #2d3a4c; height:100%; }
    .core-fill { position:absolute; left:0; right:0; bottom:0; background: linear-gradient(180deg, #7ad7ff, #2a9fd8); }
    .core-txt { position:absolute; inset:0; display:flex; align-items:center; justify-content:center; font-size:10px; color:#dff3ff; text-shadow: 0 1px 2px #000; }
    .chart { width:100%; height:64px; display:block; }
    .row2 { display:grid; grid-template-columns: 1fr 1fr; gap:8px; }
    .remote-wrap { display:grid; gap:10px; grid-template-columns: repeat(auto-fit, minmax(270px, 1fr)); }
    .remote-card .head { display:flex; justify-content:space-between; align-items:baseline; margin-bottom:6px; }
    .status-online { color: var(--ok); }
    .status-offline { color: var(--bad); }
    .metrics { display:grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap:6px; margin-bottom:6px; }
    .metric { padding:6px; border-radius:8px; background:#192230; border:1px solid #2a384a; }
    .mount-list { margin-top:6px; }
    .mount-row { display:flex; justify-content:space-between; gap:8px; font-size:11px; color:var(--muted); margin-top:2px; }
    .mount-row .m { max-width:48%; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; color:#c8d8ee; }
    .mount-row .v { text-align:right; flex:1; overflow:hidden; text-overflow:ellipsis; white-space:nowrap; }
    .hist-label { color: var(--muted); font-size:11px; margin-top:2px; margin-bottom:2px; }
    .error { color:#ff9a9a; font-size:11px; margin-top:6px; white-space:pre-wrap; word-break:break-word; }
    @media (max-width: 1080px) { .local-grid { grid-template-columns: 1fr 1fr; } .cpu-card, .net-card { grid-column: span 2; } }
    @media (max-width: 680px) { .local-grid { grid-template-columns: 1fr; } .cpu-card, .net-card { grid-column: span 1; } .top { flex-direction: column; align-items: flex-start; } }
  </style>
</head>
<body>
  <div class="top">
    <div>
      <div class="title">Dashboard</div>
      <div class="meta" id="meta">loading...</div>
    </div>
    <div class="btns">
      <button id="burstBtn" type="button">触发 3 分钟密集刷新</button>
      __AUTH_BUTTON_HTML__
    </div>
  </div>

  <div class="content">
    <div class="local-grid">
      <div class="card cpu-card">
        <h3>本机 CPU</h3>
        <div class="kv"><span class="label">总占用</span><span class="value" id="cpuTotal">--</span></div>
        <div class="kv"><span class="small" id="cpuTemp">--</span><span class="small" id="cpuLoad">--</span></div>
        <div class="core-bars" id="cpuCores"></div>
        <div class="hist-label">CPU 历史</div>
        <div id="cpuHistory" class="chart"></div>
      </div>

      <div class="card">
        <h3>本机内存</h3>
        <div class="kv"><span class="label">使用率</span><span class="value" id="memTotal">--</span></div>
        <div class="small" id="memDetail">--</div>
        <div class="hist-label">内存历史</div>
        <div id="memHistory" class="chart"></div>
      </div>

      <div class="card">
        <h3>磁盘 / 电池</h3>
        <div class="kv"><span class="label">磁盘</span><span class="value" id="diskTotal">--</span></div>
        <div class="small" id="diskDetail">--</div>
        <div class="mount-list" id="diskMounts"></div>
        <div class="kv" style="margin-top:8px;"><span class="label">电池</span><span class="value" id="batTotal">--</span></div>
        <div class="small" id="batDetail">--</div>
      </div>

      <div class="card net-card">
        <h3>本机网络</h3>
        <div class="row2">
          <div class="kv"><span class="label">下行</span><span class="value" id="rxSpeed">--</span></div>
          <div class="kv"><span class="label">上行</span><span class="value" id="txSpeed">--</span></div>
        </div>
        <div class="hist-label">网络历史（RX/TX）</div>
        <div id="netHistory" class="chart"></div>
      </div>
    </div>

    <div class="card">
      <h3>远端服务器</h3>
      <div class="remote-wrap" id="remoteWrap">
        <div class="small">加载中...</div>
      </div>
    </div>
  </div>

  <script>
    const metaEl = document.getElementById("meta");
    const cpuTotalEl = document.getElementById("cpuTotal");
    const cpuTempEl = document.getElementById("cpuTemp");
    const cpuLoadEl = document.getElementById("cpuLoad");
    const cpuCoresEl = document.getElementById("cpuCores");
    const memTotalEl = document.getElementById("memTotal");
    const memDetailEl = document.getElementById("memDetail");
    const diskTotalEl = document.getElementById("diskTotal");
    const diskDetailEl = document.getElementById("diskDetail");
    const diskMountsEl = document.getElementById("diskMounts");
    const batTotalEl = document.getElementById("batTotal");
    const batDetailEl = document.getElementById("batDetail");
    const rxSpeedEl = document.getElementById("rxSpeed");
    const txSpeedEl = document.getElementById("txSpeed");
    const cpuHistoryEl = document.getElementById("cpuHistory");
    const memHistoryEl = document.getElementById("memHistory");
    const netHistoryEl = document.getElementById("netHistory");
    const remoteWrapEl = document.getElementById("remoteWrap");
    const burstBtn = document.getElementById("burstBtn");
    let pollTimer = null;

    function hasValue(v) {
      return v !== null && v !== undefined;
    }

    function errText(e) {
      if (!hasValue(e)) return "unknown";
      if (typeof e === "string") return e;
      if (hasValue(e.message)) return String(e.message);
      try { return String(e); } catch (_) { return "unknown"; }
    }

    function esc(v) {
      return String(hasValue(v) ? v : "").replace(/[&<>"']/g, (c) => {
        if (c === "&") return "&amp;";
        if (c === "<") return "&lt;";
        if (c === ">") return "&gt;";
        if (c === '"') return "&quot;";
        return "&#39;";
      });
    }

    function pct(v, digits = 1) {
      if (v === null || v === undefined || Number.isNaN(Number(v))) return "--";
      return (Number(v) * 100).toFixed(digits) + "%";
    }

    function normalizeArray(arr) {
      if (!Array.isArray(arr)) return [];
      const out = [];
      for (const x of arr) {
        const n = Number(x);
        if (Number.isFinite(n)) out.push(n);
      }
      return out;
    }

    function groupTo8(values) {
      const src = normalizeArray(values);
      if (src.length <= 8) {
        const padded = src.slice(0);
        while (padded.length < 8) padded.push(0);
        return padded;
      }
      const out = [];
      for (let g = 0; g < 8; g++) {
        const s = Math.floor(g * src.length / 8);
        const e = Math.floor((g + 1) * src.length / 8);
        if (e <= s) { out.push(0); continue; }
        let sum = 0;
        for (let i = s; i < e; i++) sum += src[i];
        out.push(sum / (e - s));
      }
      return out;
    }

    function renderDiskMountRows(parts, maxItems = 3) {
      if (!Array.isArray(parts) || parts.length === 0) {
        return `<div class="mount-row"><span class="m">目录</span><span class="v">--</span></div>`;
      }
      const rows = [];
      for (const p of parts) {
        if (!p || !hasValue(p.mount)) continue;
        rows.push(p);
      }
      if (!rows.length) {
        return `<div class="mount-row"><span class="m">目录</span><span class="v">--</span></div>`;
      }
      rows.sort((a, b) => {
        const ma = String(a.mount || "");
        const mb = String(b.mount || "");
        if (ma === "/") return -1;
        if (mb === "/") return 1;
        return ma.localeCompare(mb);
      });
      return rows.slice(0, maxItems).map((p) => {
        const mount = esc(p.mount || "--");
        const used = esc(p.used || "--");
        const size = esc(p.size || "--");
        const percent = pct(p.percent, 0);
        return `<div class="mount-row"><span class="m">${mount}</span><span class="v">${used}/${size} · ${percent}</span></div>`;
      }).join("");
    }

    function toSeries(values, tsList) {
      const vals = normalizeArray(values);
      const ts = normalizeArray(tsList);
      const out = [];
      if (!vals.length) return out;
      if (ts.length === vals.length) {
        for (let i = 0; i < vals.length; i++) out.push([ts[i], vals[i]]);
        return out;
      }
      for (let i = 0; i < vals.length; i++) out.push([i, vals[i]]);
      return out;
    }

    function sparkline(values, tsList, color, fill, width = 300, height = 64) {
      const series = toSeries(values, tsList);
      if (!series.length) return `<svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}"><text x="6" y="16" fill="#7f95b0" font-size="11">--</text></svg>`;
      const arr = series.map((p) => p[1]);
      const xs = series.map((p) => p[0]);
      let min = Math.min(...arr);
      let max = Math.max(...arr);
      if (!(max > min)) { max = min + 1; }
      let minX = Math.min(...xs);
      let maxX = Math.max(...xs);
      if (!(maxX > minX)) { maxX = minX + 1; }
      const points = series.map((p) => {
        const x = 1 + ((p[0] - minX) / (maxX - minX)) * (width - 2);
        const v = p[1];
        const y = height - 2 - ((v - min) / (max - min)) * (height - 6);
        return `${x.toFixed(1)},${y.toFixed(1)}`;
      }).join(" ");
      let fillPath = "";
      if (fill) {
        const first = points.split(" ")[0].split(",");
        const last = points.split(" ").slice(-1)[0].split(",");
        fillPath = `<polygon points="${first[0]},${height-2} ${points} ${last[0]},${height-2}" fill="${fill}" />`;
      }
      return `<svg width="100%" height="${height}" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
        <polyline points="${points}" fill="none" stroke="${color}" stroke-width="1.8" />
        ${fillPath}
      </svg>`;
    }

    function dualSparkline(rxValues, rxTs, txValues, txTs, width = 300, height = 64) {
      const rx = toSeries(rxValues, rxTs);
      const tx = toSeries(txValues, txTs);
      if (!rx.length && !tx.length) return sparkline([], [], "#55efc4", "", width, height);

      const allVals = rx.map((p) => p[1]).concat(tx.map((p) => p[1]));
      const allX = rx.map((p) => p[0]).concat(tx.map((p) => p[0]));
      let min = Math.min(...allVals);
      let max = Math.max(...allVals);
      if (!(max > min)) { max = min + 1; }
      let minX = Math.min(...allX);
      let maxX = Math.max(...allX);
      if (!(maxX > minX)) { maxX = minX + 1; }
      const toPoints = (arr) => arr.map((p) => {
        const x = 1 + ((p[0] - minX) / (maxX - minX)) * (width - 2);
        const v = p[1];
        const y = height - 2 - ((v - min) / (max - min)) * (height - 6);
        return `${x.toFixed(1)},${y.toFixed(1)}`;
      }).join(" ");
      return `<svg width="100%" height="${height}" viewBox="0 0 ${width} ${height}" preserveAspectRatio="none">
        <polyline points="${toPoints(rx)}" fill="none" stroke="#55efc4" stroke-width="1.8" />
        <polyline points="${toPoints(tx)}" fill="none" stroke="#ffb067" stroke-width="1.8" />
      </svg>`;
    }

    function renderLocal(local) {
      cpuTotalEl.textContent = pct(local.cpuTotal);
      cpuTempEl.textContent = `温度 ${local.cpuTemp || "--"}`;
      cpuLoadEl.textContent = `Load ${local.loadAverage || "--"}`;
      memTotalEl.textContent = pct(local.memPercent);
      memDetailEl.textContent = local.memDetail || "--";
      diskTotalEl.textContent = pct(local.diskPercent);
      diskDetailEl.textContent = local.diskRootUsage || "--";
      diskMountsEl.innerHTML = renderDiskMountRows(local.diskPartitions || [], 3);
      batTotalEl.textContent = `${hasValue(local.batPercent) ? local.batPercent : "--"}%`;
      batDetailEl.textContent = local.batState || "--";
      rxSpeedEl.textContent = local.netRxSpeed || "--";
      txSpeedEl.textContent = local.netTxSpeed || "--";

      const cores = groupTo8(local.cpuCores || []);
      cpuCoresEl.innerHTML = cores.map((v) => {
        const p = Math.max(0, Math.min(100, Number(v) * 100));
        return `<div class="core-bar"><div class="core-fill" style="height:${p.toFixed(1)}%"></div><div class="core-txt">${p.toFixed(0)}</div></div>`;
      }).join("");

      cpuHistoryEl.innerHTML = sparkline(local.cpuHistory || [], local.cpuHistoryTs || [], "#4fc3f7", "rgba(79,195,247,0.16)");
      memHistoryEl.innerHTML = sparkline(local.memHistory || [], local.memHistoryTs || [], "#8ea5ff", "rgba(142,165,255,0.14)");
      netHistoryEl.innerHTML = dualSparkline(
        local.netRxHistory || [],
        local.netRxHistoryTs || [],
        local.netTxHistory || [],
        local.netTxHistoryTs || []
      );
    }

    function renderRemote(list) {
      if (!Array.isArray(list) || list.length === 0) {
        remoteWrapEl.innerHTML = "<div class='small'>未配置远端主机</div>";
        return;
      }
      remoteWrapEl.innerHTML = list.map((it) => {
        const online = String(it.status || "").toLowerCase() === "online";
        const stCls = online ? "status-online" : "status-offline";
        const coreBars = groupTo8(it.cpuGroups || []).map((v) => {
          const p = Math.max(0, Math.min(100, Number(v) * 100));
          return `<div class="core-bar"><div class="core-fill" style="height:${p.toFixed(1)}%"></div><div class="core-txt">${p.toFixed(0)}</div></div>`;
        }).join("");
        const errorHtml = it.error ? `<div class="error">${esc(it.error)}</div>` : "";
        const mountsHtml = `<div class="mount-list">${renderDiskMountRows(it.diskPartitions || [], 3)}</div>`;
        return `<div class="card remote-card">
          <div class="head">
            <h3>${esc(it.name || "--")}</h3>
            <div class="small ${stCls}">${esc(it.status || "--")} · ${esc(it.lastUpdate || "--")}</div>
          </div>
          <div class="metrics">
            <div class="metric"><div class="label">CPU</div><div class="value">${pct(it.cpuTotal)}</div></div>
            <div class="metric"><div class="label">内存</div><div class="value">${pct(it.memPercent)}</div></div>
            <div class="metric"><div class="label">磁盘</div><div class="value">${pct(it.diskPercent)}</div></div>
          </div>
          <div class="small">MEM ${esc(it.memDetail || "--")} · DISK ${esc(it.diskDetail || "--")} · Load ${esc(it.loadAvg || "--")}</div>
          ${mountsHtml}
          <div class="core-bars" style="margin-top:6px;">${coreBars}</div>
          <div class="hist-label">CPU 历史</div>
          <div class="chart">${sparkline(it.cpuHistory || [], it.cpuHistoryTs || [], "#4fc3f7", "rgba(79,195,247,0.16)")}</div>
          <div class="hist-label">内存历史</div>
          <div class="chart">${sparkline(it.memHistory || [], it.memHistoryTs || [], "#8ea5ff", "rgba(142,165,255,0.14)")}</div>
          ${errorHtml}
        </div>`;
      }).join("");
    }

    async function fetchSnapshot() {
      const res = await fetch("/api/snapshot", { cache: "no-store" });
      if (res.status === 401) {
        location.href = "/login";
        return;
      }
      if (!res.ok) {
        throw new Error(`HTTP ${res.status}`);
      }
      let data = null;
      try {
        data = await res.json();
      } catch (e) {
        throw new Error(`JSON 解析失败: ${errText(e)}`);
      }
      const burstText = data.burstActive
        ? `密集刷新中，剩余 ${data.burstRemainingSec}s（${data.pollIntervalSec}s/次）`
        : `常规刷新 ${data.pollIntervalSec}s/次`;
      const ts = new Date(data.timestampMs || Date.now()).toLocaleTimeString();
      metaEl.textContent = `${burstText} · ${ts} · __WEB_UI_VERSION__`;
      try {
        renderLocal(data.local || {});
        renderRemote(data.remoteServers || []);
      } catch (e) {
        throw new Error(`页面渲染失败: ${errText(e)}`);
      }
      return data;
    }

    async function startPolling() {
      if (pollTimer) clearTimeout(pollTimer);
      let nextMs = 5000;
      try {
        const data = await fetchSnapshot();
        const pollSec = hasValue(data) && hasValue(data.pollIntervalSec) ? Number(data.pollIntervalSec) : 5;
        nextMs = Math.max(3000, Math.min(10000, pollSec * 1000));
      } catch (e) {
        const msg = errText(e);
        metaEl.textContent = `数据获取失败：${msg}；5 秒后重试`;
        remoteWrapEl.innerHTML = `<div class='small'>远端数据加载失败：${esc(msg)}，正在重试...</div>`;
      }
      pollTimer = setTimeout(() => {
        startPolling();
      }, nextMs);
    }

    burstBtn.addEventListener("click", async () => {
      try {
        await fetch("/api/burst", { method: "POST" });
        await startPolling();
      } catch (e) {
      }
    });

    startPolling();
  </script>
</body>
</html>"""
        return page.replace("__AUTH_BUTTON_HTML__", auth_button_html).replace("__WEB_UI_VERSION__", WEB_UI_VERSION)


def parse_host_port(bind_text: str, default_port: int) -> Tuple[str, int]:
    text = bind_text.strip()
    if not text:
        return "0.0.0.0", default_port
    if ":" in text and not text.startswith("["):
        host, port_text = text.rsplit(":", 1)
        try:
            return host, int(port_text)
        except ValueError:
            return host, default_port
    return text, default_port


def main() -> int:
    bind = env_text("ORBITAL_WEB_BIND", "0.0.0.0")
    port = env_int("ORBITAL_WEB_PORT", 18911, 1, 65535)
    bind, port = parse_host_port(bind, port)

    sampler = OrbitalSampler()
    OrbitalHandler.sampler = sampler
    sampler.start()

    server = ThreadingHTTPServer((bind, port), OrbitalHandler)
    server.daemon_threads = True

    addr = server.server_address
    host = addr[0]
    if host == "0.0.0.0":
        try:
            host = socket.gethostbyname(socket.gethostname())
        except OSError:
            host = "0.0.0.0"

    print(
        f"[orbital_web] listening on {addr[0]}:{addr[1]} "
        f"(user={sampler.username}, base={sampler.base_interval_sec}s, burst={sampler.burst_interval_sec}s/{sampler.burst_duration_sec}s)",
        flush=True,
    )
    print(f"[orbital_web] open http://{host}:{addr[1]}/", flush=True)

    try:
        server.serve_forever(poll_interval=0.5)
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
        sampler.stop()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
