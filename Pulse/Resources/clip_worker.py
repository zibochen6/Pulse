"""Run one local talking-head job and atomically expose its real progress to Pulse."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import queue
import threading
import time

PLATFORMS = ("douyin", "xiaohongshu", "kuaishou", "bilibili")
SKILL = ".agents/skills/talking-head-autoclip/SKILL.md"
RECEIPT = ".pulse-clip.json"
DRAFT_STATES = {"saved_verified", "saved_unverified", "page_only", "needs_login", "blocked", "pending"}


def read_json(path):
    try:
        with path.open() as handle:
            value = json.load(handle)
        return value if isinstance(value, dict) else {}
    except (OSError, ValueError):
        return {}


def save_json(path, value):
    with tempfile.NamedTemporaryFile("w", dir=path.parent, delete=False) as handle:
        try:
            json.dump(value, handle, ensure_ascii=False)
            handle.flush()
            os.replace(handle.name, path)
        finally:
            Path(handle.name).unlink(missing_ok=True)


def digest(path):
    result = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            result.update(block)
    return result.hexdigest()


def inside(root, location):
    if not isinstance(location, str) or not location:
        return None
    path = (root / location).resolve()
    return path if root in path.parents and path.is_file() and path.stat().st_size else None


def review_page(folder):
    for pattern in ("*/review.html", "*/quality-preview.html"):
        for path in sorted(folder.glob(pattern)):
            if inside(folder, str(path)):
                return str(path)
    return None


def package_file(folder, package, location):
    if not isinstance(location, str) or not location:
        return None
    return inside(folder, str(package.parent / location)) or inside(folder, location)


def media_files(folder, package):
    if not package:
        return None, False
    data = read_json(package)
    video = package_file(folder, package, data.get("video"))
    subtitles = package_file(folder, package, data.get("srt"))
    ratios = {cover.get("ratio") for cover in data.get("covers", [])
              if isinstance(cover, dict) and package_file(folder, package, cover.get("path"))}
    return video, bool(video and subtitles and {"16:9", "4:3", "3:4", "9:16"} <= ratios)


def find_job(output, stem, fingerprint):
    """Match old normalized sources by content even when a recording was renamed."""
    preferred = output / stem
    for folder in sorted(output.iterdir(), key=lambda path: path != preferred):
        if not folder.is_dir() or folder.is_symlink():
            continue
        receipt = read_json(folder / RECEIPT)
        if receipt.get("fingerprint") == fingerprint:
            return folder, receipt
        for manifest in folder.glob("*.normalize.json"):
            source = read_json(manifest).get("identity", {}).get("source", {})
            if source.get("sha256") == fingerprint:
                if any(package_file(folder, p, read_json(p).get("video")) for p in folder.glob("*/package.json")):
                    return folder, {"phase": "existing"}
                return folder, {}
    folder = preferred
    if folder.exists():
        folder = output / (stem + "-" + fingerprint[:12])
    if folder.exists():
        raise ValueError("Output folder already exists with a different source.")
    return folder, {}


def image_proof(root, proof):
    if not isinstance(proof, dict):
        return None
    path = inside(root, proof.get("path"))
    if not path:
        return None
    with path.open("rb") as handle:
        header = handle.read(8)
    if not (header == b"\x89PNG\r\n\x1a\n" or header.startswith(b"\xff\xd8\xff")):
        return None
    actual = digest(path)
    return actual if actual == proof.get("sha256") else None


def outcomes(folder, report, video_hash):
    rows = []
    used = set()
    for name in PLATFORMS:
        item = report.get("platforms", {}).get(name, {})
        claimed = item.get("status", "pending")
        status = claimed
        if status not in DRAFT_STATES:
            status = "pending"
        if status in {"saved_verified", "saved_unverified"}:
            saved = image_proof(folder, item.get("save"))
            restored = image_proof(folder, item.get("restore"))
            if not saved or saved in used or not video_hash or item.get("video_sha256") != video_hash:
                status = "pending"
            elif status == "saved_verified" and (
                not restored or restored == saved or restored in used
                or set(item.get("restored_fields", [])) != {"video", "copy", "topics", "covers"}
            ):
                status = "saved_unverified"
            if saved:
                used.add(saved)
            if restored:
                used.add(restored)
        detail = str(item.get("detail", ""))[:260] if claimed == status else "clip.incompleteEvidence"
        rows.append({"platform": name, "status": status, "detail": detail})
    return rows


def prompt_for(source, folder, fingerprint, language):
    return f"""Use the local talking-head-autoclip skill at {SKILL}. Execute this job now.
Source: {json.dumps(str(source))}. SHA256: {fingerprint}.
Use only this source. All new media, platform evidence, review pages, and intermediate files go under
{json.dumps(str(folder))}. Leave existing inputs and completed versions intact.
First inspect a frame and the audio/content. If it is not a talking-head recording, stop before editing or uploading and return not_a_talk.
Perform the skill's full edit, transcript, mix, visual QA, and real-frame image-generation cover workflow.
The user delegates choosing the cover title from this recording to you. No intermediate title approval is needed.
Use the accounts and platform instructions in the workspace skill. Prepare drafts only on Douyin, Xiaohongshu,
Kuaishou and Bilibili. Never call submit or click final publish, schedule or post. Verify each account.
For each platform save and reopen the draft; inspect video, copy, native topics and every cover slot.
Record screenshots with their actual hashes, using the skill's ledger where supported. A live editor is page_only.
On login/captcha or an unavailable platform, keep that page, mark it and continue other platforms.
Before retries inspect this job's existing assets, draft IDs and pages. Reuse verified drafts.
Read the previous pulse-draft-report.json on retries and preserve existing media, copies and draft evidence.
Do not replay an uncertain upload, overwrite another draft or infer a save from an upload.
A draft-ready run needs its actual package and review HTML. Respond with ONE JSON object, no code fence.
Use {language} for human-facing detail. Shape:
{{"outcome":"edited|not_a_talk|blocked", "message":"brief result or actionable cause",
"package":"relative path to the actual package.json","review":"relative path to review.html",
"platforms":{{"douyin":{{"status":"saved_verified|saved_unverified|page_only|needs_login|blocked|pending",
"detail":"short observation","save":{{"path":"relative screenshot","sha256":"actual SHA256"}},
"restore":{{"path":"relative screenshot","sha256":"actual SHA256"}},"restored_fields":["video","copy","topics","covers"],"video_sha256":"SHA256 of the uploaded final video"}}}}}}
Include all four platform keys: {', '.join(PLATFORMS)}. List only fields actually checked after reopening. Use null for missing screenshots and empty strings for missing paths.
Do not manufacture evidence or report unperformed listening. If blocked still return the available results."""


def result_schema():
    def record(fields):
        return {"type": "object", "properties": fields, "additionalProperties": False, "required": list(fields)}

    string = {"type": "string"}
    proof = record({"path": string, "sha256": string})
    optional_proof = {"anyOf": [proof, {"type": "null"}]}
    row = record({"status": {"enum": sorted(DRAFT_STATES), "type": "string"}, "detail": string,
                  "save": optional_proof, "restore": optional_proof, "video_sha256": string,
                  "restored_fields": {"type": "array", "items": {"type": "string",
                      "enum": ["video", "copy", "topics", "covers"]}}})
    return record({"outcome": {"type": "string", "enum": ["edited", "not_a_talk", "blocked"]},
                   "message": string, "package": string, "review": string,
                   "platforms": record({name: row for name in PLATFORMS})})


def artifact_activity(folder, since):
    patterns = (("*.normalize.json", "normalizing"), ("transcript/chunks/*.json", "transcribing"),
                ("*/covers/cover-request.json", "covers"), ("*/covers/cover-result.json", "covers"),
                ("*/media-package.json", "rendering"), ("*/package.json", "rendering"),
                ("*/publication.json", "drafting"))
    newest = since, None
    for pattern, stage in patterns:
        for path in folder.glob(pattern):
            try:
                modified = path.stat().st_mtime_ns
            except FileNotFoundError:
                continue
            if modified > newest[0]:
                newest = modified, stage
                if stage == "drafting":
                    events = read_json(path).get("events") or []
                    platform = events[-1].get("platform") if events else None
                    if platform in PLATFORMS:
                        newest = modified, "drafting." + platform
    return newest


def stream_events(pipe, folder):
    # A long media command can produce files without producing a new Codex JSON event.
    inbox = queue.Queue(maxsize=40)
    def read_lines():
        try:
            for line in pipe:
                inbox.put(line)
        finally:
            inbox.put(None)
    threading.Thread(target=read_lines, daemon=True).start()
    since = time.time_ns()
    next_check = time.monotonic() + 2
    while True:
        try:
            line = inbox.get(timeout=max(0, next_check - time.monotonic()))
            if line is None:
                return
            try:
                yield json.loads(line)
            except ValueError:
                pass
        except queue.Empty:
            pass
        if time.monotonic() >= next_check:
            since, stage = artifact_activity(folder, since)
            next_check = time.monotonic() + 2
            if stage:
                yield {"type": "artifact", "stage": stage}


def launch_env():
    env = os.environ.copy()
    home = Path.home()
    paths = [home / ".local/bin", Path("/opt/homebrew/bin"), Path("/usr/local/bin")]
    nvm = home / ".nvm/versions/node"
    if nvm.is_dir():
        nodes = sorted(nvm.glob("v*/bin"), key=lambda p: tuple(map(int, re.findall(r"\d+", p.parent.name))), reverse=True)
        paths.extend(nodes[:1])
    env["PATH"] = os.pathsep.join([*map(str, paths), env.get("PATH", "/usr/bin:/bin")])
    return env


def activity(item):
    kind = item.get("type")
    if kind == "command_execution":
        command = item.get("command", "")
        for operation, stage in (("transcribe.py", "transcribing"), ("normalize.sh", "normalizing"),
                                 ("workflow.py prepare", "rendering"), ("workflow.py stage", "drafting"),
                                 ("workflow.py cover-", "covers"), ("workflow.py draft-record", "checkingDrafts")):
            if operation in command:
                return stage
        return "command"
    if kind == "mcp_tool_call":
        return "covers" if "imagegen" in str(item.get("tool", "")) else "tool"
    if kind == "agent_message":
        return "response"
    return None


def run(args, state, update):
    root = args.workspace.resolve()
    if not (root / SKILL).is_file():
        raise ValueError("Workspace is missing talking-head-autoclip.")
    output = root / "output"
    output.mkdir(exist_ok=True)
    source = args.source.resolve(strict=True)
    before = source.stat()
    fingerprint = digest(source)
    after = source.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ValueError("Recording is still changing.")
    folder, previous = find_job(output, source.stem, fingerprint)
    previous_phase = previous.get("phase")
    if previous_phase in {"completed", "existing", "noClip"}:
        update(phase="noClip", folder=str(folder) if previous_phase != "noClip" else None,
               review=review_page(folder), platforms=previous.get("platforms", []))
        return
    folder.mkdir(exist_ok=True)
    state.update(folder=str(folder), fingerprint=fingerprint)
    # Mark ownership before a subprocess can perform an external action.
    save_json(folder / RECEIPT, state)
    update(activity="launch")
    with tempfile.TemporaryDirectory(dir=args.support) as temp:
        final = Path(temp) / "result.txt"
        schema = Path(temp) / "schema.json"
        save_json(schema, result_schema())
        command = [str(args.codex), "exec", "--json", "--skip-git-repo-check", "-C", str(root),
                   "--model", args.model, "-c", "model_reasoning_effort=" + json.dumps(args.effort),
                   "--output-schema", str(schema), "--output-last-message", str(final), "-"]
        with subprocess.Popen(command, cwd=root, env=launch_env(), stdin=subprocess.PIPE,
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL) as proc:
            proc.stdin.write(prompt_for(source, folder, fingerprint, args.language).encode())
            proc.stdin.close()
            finished = False
            failure = ""
            for event in stream_events(proc.stdout, folder):
                kind = event.get("type")
                if kind == "turn.started":
                    update(phase="running", activity="turn")
                elif kind == "turn.completed":
                    finished = True
                    update(phase="checking", activity="checkingDrafts")
                elif kind == "turn.failed":
                    failure = str(event.get("error", {}).get("message", ""))[:350]
                    update(phase="checking", detail=failure, activity="stopping")
                elif kind == "artifact" and state["phase"] == "running":
                    update(activity=event["stage"])
                elif kind in {"item.started", "item.completed", "item.updated"} and state["phase"] == "running":
                    stage = activity(event.get("item", {}))
                    if stage:
                        update(activity=stage)
                elif kind == "error":
                    failure = str(event.get("message", ""))[:350]
            code = proc.wait()
        if code or not finished:
            raise ValueError(failure or f"Codex exited before completing the turn ({code}).")
        report = read_json(final)
    if not report:
        raise ValueError("Codex did not return a readable draft report.")
    save_json(folder / "pulse-draft-report.json", report)
    if report.get("outcome") == "not_a_talk":
        update(phase="noClip", detail=report.get("message", ""))
    else:
        package = inside(folder, report.get("package"))
        video, media_complete = media_files(folder, package)
        rows = outcomes(folder, report, digest(video) if video else None)
        review = inside(folder, report.get("review"))
        if review and review.suffix.lower() != ".html":
            review = None
        complete = report.get("outcome") == "edited" and media_complete and review and all(
            row["status"] == "saved_verified" for row in rows)
        detail = str(report.get("message", ""))[:450]
        if report.get("outcome") == "edited" and not (media_complete and review):
            detail = "clip.incompletePackage"
        elif any(row["detail"] == "clip.incompleteEvidence" for row in rows):
            detail = "clip.incompleteEvidence"
        update(phase="completed" if complete else "attention", platforms=rows,
               review=str(review) if review else review_page(folder), detail=detail)


def main():
    parser = argparse.ArgumentParser()
    for name in ("workspace", "source", "codex", "support"):
        parser.add_argument("--" + name, type=Path, required=True)
    for name in ("model", "effort", "id", "language"):
        parser.add_argument("--" + name, required=True)
    args = parser.parse_args()
    args.support.mkdir(mode=0o700, parents=True, exist_ok=True)
    with (args.support / "worker.lock").open("a") as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            return os.EX_TEMPFAIL
        state = {"id": args.id, "source": args.source.name, "started": time.time(), "phase": "starting",
                 "model": args.model, "effort": args.effort, "platforms": []}

        def update(**fields):
            state.update(fields, updated=time.time())
            if state["phase"] in {"failed", "attention", "completed", "noClip"} and state.get("fingerprint"):
                save_json(Path(state["folder"]) / RECEIPT, state)
            save_json(args.support / "latest.json", state)

        update(activity="fingerprint")
        try:
            run(args, state, update)
        except Exception as error:
            update(phase="failed", detail=str(error)[:450])
            return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
