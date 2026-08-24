"""Download queue worker pool.

Replaces the old fixed "express"/"normal" two-slot system: a configurable
number of worker threads (`ANIWORLD_MAX_CONCURRENT_DOWNLOADS`, default 3)
each pick the next queued item whose *bucket* isn't already downloading
something. A bucket is a profile (so each profile gets its own effectively
serial pipeline, but different profiles can download in parallel up to the
concurrency cap) — auto-sync items (which have no profile) all share one
synthetic bucket so they stay serialized among themselves, same as before.

Priority still decides pick order within the eligible items (0=watch-intent,
1=prefetch, 2=manual, 3=autosync), and a P0 watch-intent still preempts a P1
prefetch running in the *same* bucket — see maybe_preempt_for_p0().
"""

import json
import os
import threading
import time
from pathlib import Path

from ..logger import get_logger
from ..providers import resolve_provider
from .db import (
    cancel_flags,
    get_custom_path_by_id,
    get_queue_item,
    get_queued_items_by_priority,
    is_queue_cancelled,
    request_cancel,
    reset_stale_running,
    set_queue_status,
    update_queue_errors,
    update_queue_progress,
)

logger = get_logger(__name__)

_AUTOSYNC_BUCKET = "_autosync"

_pool_lock = threading.Lock()
_busy_buckets: dict = {}       # bucket_key -> queue_id currently downloading
_thread_registry: dict = {}    # queue_id -> OS thread ident (for kill_active_ffmpeg)
_preempt_ids: set = set()      # queue_ids flagged to be preempted (a P0 wants their bucket)

_started = False
_start_lock = threading.Lock()

IDLE_SECONDS = 2


def _max_concurrent():
    try:
        n = int(os.environ.get("ANIWORLD_MAX_CONCURRENT_DOWNLOADS", "3"))
    except ValueError:
        n = 3
    return max(1, n)


def _bucket_key(item):
    profile_id = item.get("profile_id")
    return profile_id if profile_id is not None else _AUTOSYNC_BUCKET


def ensure_started():
    """Start the worker pool once per process."""
    global _started
    with _start_lock:
        if _started:
            return
        _started = True
    reset_stale_running()
    n = _max_concurrent()
    for i in range(n):
        threading.Thread(
            target=_run, name=f"aniworld-download-worker-{i}", daemon=True
        ).start()
    logger.info("Download worker pool started with %d slot(s)", n)


def thread_id_for(queue_id):
    """OS thread ident currently downloading *queue_id*, or None."""
    with _pool_lock:
        return _thread_registry.get(queue_id)


def maybe_preempt_for_p0(item):
    """Call right after enqueueing a P0 item to interrupt a P1 in its bucket."""
    from ..models.common.common import kill_active_ffmpeg

    bucket = _bucket_key(item)
    with _pool_lock:
        running_id = _busy_buckets.get(bucket)
        if running_id is None:
            return
        running_item = get_queue_item(running_id)
        if not running_item or running_item.get("priority", 2) != 1:
            return  # only preempt a P1 prefetch, never another P0
        _preempt_ids.add(running_id)
        thread_id = _thread_registry.get(running_id)

    logger.info(
        "Preempting P1 item %d for an incoming P0 watch-intent in the same bucket",
        running_id,
    )
    if thread_id is not None:
        kill_active_ffmpeg(thread_id=thread_id)


def _claim_next():
    with _pool_lock:
        for item in get_queued_items_by_priority():
            bucket = _bucket_key(item)
            if bucket in _busy_buckets:
                continue
            try:
                set_queue_status(item["id"], "running")
            except Exception:
                logger.exception("Could not mark queue item %s as running", item["id"])
                return None, None
            _busy_buckets[bucket] = item["id"]
            _thread_registry[item["id"]] = threading.current_thread().ident
            return item, bucket
    return None, None


def _release(queue_id, bucket):
    with _pool_lock:
        if _busy_buckets.get(bucket) == queue_id:
            del _busy_buckets[bucket]
        _thread_registry.pop(queue_id, None)
        _preempt_ids.discard(queue_id)


def _build_selected_path(item):
    """Compute the output directory for a queue item (None = use default)."""
    lang_sep = os.environ.get("ANIWORLD_LANG_SEPARATION", "0") == "1"
    if item.get("source") == "sync:all_langs":
        lang_sep = True

    custom_path_id = item.get("custom_path_id")
    base = None
    if custom_path_id:
        cp = get_custom_path_by_id(custom_path_id)
        if cp:
            base = Path(cp["path"]).expanduser()
            if not base.is_absolute():
                base = Path.home() / base

    if base is None:
        raw = os.environ.get("ANIWORLD_DOWNLOAD_PATH", "")
        if raw:
            base = Path(raw).expanduser()
            if not base.is_absolute():
                base = Path.home() / base
        else:
            base = Path.home() / "Downloads"

    if lang_sep:
        lang_folder_map = {
            "German Dub": "german-dub",
            "English Sub": "english-sub",
            "German Sub": "german-sub",
            "English Dub": "english-dub",
        }
        lang_folder = lang_folder_map.get(
            item["language"], item["language"].lower().replace(" ", "-")
        )
        return str(base / lang_folder)
    if custom_path_id:
        return str(base)
    return None


def _process(item):
    """Download all episodes for *item*. Returns True if it was preempted."""
    from ..models.common.common import bind_progress_to_queue_item, clear_progress
    from ..playwright import captcha as _captcha_mod

    queue_id = item["id"]
    bind_progress_to_queue_item(queue_id)
    episodes = json.loads(item["episodes"])
    errors = []
    selected_path = _build_selected_path(item)

    try:
        for i, ep_url in enumerate(episodes):
            if queue_id in _preempt_ids:
                logger.info(
                    "Preempted before episode %d for '%s' — requeueing", i, item["title"]
                )
                set_queue_status(queue_id, "queued")
                update_queue_progress(queue_id, 0, "")
                return True

            update_queue_progress(queue_id, i, ep_url)
            try:
                prov = resolve_provider(ep_url)
                ep_kwargs = {
                    "url": ep_url,
                    "selected_language": item["language"],
                    "selected_provider": item["provider"],
                }
                if selected_path:
                    ep_kwargs["selected_path"] = selected_path
                episode = prov.episode_cls(**ep_kwargs)
                _captcha_mod._local.queue_id = queue_id
                try:
                    episode.download()
                finally:
                    _captcha_mod._local.queue_id = None
            except Exception as e:
                _captcha_mod._local.queue_id = None
                if queue_id in _preempt_ids:
                    logger.info(
                        "Preempted mid-episode for '%s' — requeueing", item["title"]
                    )
                    set_queue_status(queue_id, "queued")
                    update_queue_progress(queue_id, 0, "")
                    return True
                logger.error(f"Download failed for {ep_url}: {e}")
                errors.append({"url": ep_url, "error": str(e)})
                update_queue_errors(queue_id, json.dumps(errors))

            cancelled, forced = cancel_flags(queue_id)
            if cancelled:
                logger.info(
                    "Download %s for queue item %s",
                    "force cancelled" if forced else "cancelled",
                    queue_id,
                )
                done = i if forced else i + 1
                update_queue_progress(queue_id, done, "")
                everything_done = not forced and done >= len(episodes) and not errors
                set_queue_status(
                    queue_id, "completed" if everything_done else "cancelled"
                )
                return False
            # Legacy status-based cancel (still set by anything using the old
            # cancel_queue_item path directly) — treat the same as above.
            if is_queue_cancelled(queue_id):
                update_queue_progress(queue_id, i + 1, "")
                return False

        update_queue_progress(queue_id, len(episodes), "")
        status = "failed" if errors and len(errors) == len(episodes) else "completed"
        set_queue_status(queue_id, status)
        return False
    finally:
        bind_progress_to_queue_item(None)
        clear_progress(queue_id)


def _run():
    while True:
        item = None
        bucket = None
        try:
            item, bucket = _claim_next()
            if not item:
                time.sleep(IDLE_SECONDS)
                continue
            logger.info(
                "Bucket %s: P%d '%s'", bucket, item.get("priority", 2), item["title"]
            )
            _process(item)
        except Exception:
            logger.error("Download worker error", exc_info=True)
            if item:
                try:
                    set_queue_status(item["id"], "failed")
                except Exception:
                    pass
            time.sleep(3)
        finally:
            if item:
                _release(item["id"], bucket)


__all__ = [
    "ensure_started",
    "thread_id_for",
    "maybe_preempt_for_p0",
    "request_cancel",
]
