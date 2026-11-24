"""Offline regression checks for the packaged clip worker. Run with python3 -B."""
import hashlib
import importlib.util
from pathlib import Path
import tempfile
import shutil
import subprocess
import sys
import unittest


SCRIPT = Path(__file__).resolve().parents[2] / "Pulse/Resources/clip_worker.py"
SPEC = importlib.util.spec_from_file_location("clip_worker", SCRIPT)
worker = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(worker)


class ClipWorkerTests(unittest.TestCase):
    def setUp(self):
        temp = tempfile.TemporaryDirectory()
        self.addCleanup(temp.cleanup)
        self.root = Path(temp.name).resolve()

    def proof(self, name):
        path = self.root / (name + ".png")
        data = b"\x89PNG\r\n\x1a\n" + name.encode()
        path.write_bytes(data)
        return {"path": path.name, "sha256": hashlib.sha256(data).hexdigest()}

    def row(self, name):
        return {"status": "saved_verified", "save": self.proof(name + "-save"),
                "restore": self.proof(name + "-restore"), "detail": "fixture",
                "restored_fields": ["video", "copy", "topics", "covers"], "video_sha256": "clip-hash"}

    def outcomes(self, **platforms):
        return {r["platform"]: r["status"] for r in worker.outcomes(
            self.root, {"platforms": platforms}, "clip-hash")}

    def test_independent_platforms_and_partial_login(self):
        result = self.outcomes(douyin=self.row("douyin"), bilibili=self.row("bilibili"),
                               kuaishou={"status": "needs_login"}, xiaohongshu={"status": "page_only"})
        self.assertEqual(result, {"douyin": "saved_verified", "bilibili": "saved_verified",
                                  "kuaishou": "needs_login", "xiaohongshu": "page_only"})

    def test_foreign_video_or_unconfirmed_topics_downgrade_verification(self):
        one = self.row("douyin")
        one["video_sha256"] = "other"
        two = self.row("bilibili")
        two["restored_fields"].remove("topics")
        result = self.outcomes(douyin=one, bilibili=two)
        self.assertEqual(result["douyin"], "pending")
        self.assertEqual(result["bilibili"], "saved_unverified")

    def test_stale_changed_shared_and_outside_screenshots_do_not_verify(self):
        first = self.row("douyin")
        second = self.row("bilibili")
        second["restore"] = first["restore"]
        third = self.row("kuaishou")
        third["restore"]["sha256"] = "wrong"
        fourth = self.row("xiaohongshu")
        fourth["save"]["path"] = "../foreign.png"
        (self.root / "symlink").symlink_to(self.root.parent)
        self.assertIsNone(worker.inside(self.root, "symlink"))
        result = self.outcomes(douyin=first, bilibili=second, kuaishou=third, xiaohongshu=fourth)
        self.assertEqual(result, {"douyin": "saved_verified", "bilibili": "saved_unverified",
                                  "kuaishou": "saved_unverified", "xiaohongshu": "pending"})

    def test_renamed_legacy_source_and_colliding_new_filename(self):
        folder = self.root / "IMG_20"
        version = folder / "v1"
        version.mkdir(parents=True)
        video = version / "clip.mp4"
        video.write_bytes(b"video")
        worker.save_json(version / "package.json", {"video": str(video)})
        worker.save_json(folder / "master.mp4.normalize.json", {"identity": {"source": {"sha256": "abc"}}})
        self.assertEqual(worker.find_job(self.root, "rec_88", "abc"), (folder, {"phase": "existing"}))
        self.assertEqual(worker.find_job(self.root, "IMG_20", "different"), (self.root / "IMG_20-different", {}))

    def test_active_or_partial_work_reuses_its_own_folder(self):
        folder = self.root / "rec_30"
        folder.mkdir()
        for phase in ("starting", "attention", "completed", "noClip"):
            record = {"fingerprint": "abc", "phase": phase}
            worker.save_json(folder / worker.RECEIPT, record)
            self.assertEqual(worker.find_job(self.root, "IMG_77", "abc"), (folder, record))

    def test_complete_media_needs_subtitles_and_all_four_covers_inside_job(self):
        package = self.root / "v1" / "package.json"
        package.parent.mkdir()
        assets = {"video": "clip.mp4", "srt": "clip.srt", "covers": []}
        for name in ("clip.mp4", "clip.srt"):
            (package.parent / name).write_bytes(b"fixture")
        for ratio in ("3:4", "4:3", "16:9", "9:16"):
            name = ratio.replace(":", "x") + ".png"
            (package.parent / name).write_bytes(b"cover")
            assets["covers"].append({"path": name, "ratio": ratio})
        worker.save_json(package, assets)
        self.assertTrue(worker.media_files(self.root, package)[1])
        (package.parent / "3x4.png").unlink()
        self.assertFalse(worker.media_files(self.root, package)[1])

    def test_worker_verifies_result_then_skips_same_content_under_another_name(self):
        fixture = self.root / "fixture"
        version = fixture / "v1"
        version.mkdir(parents=True)
        skill = self.root / worker.SKILL
        skill.parent.mkdir(parents=True)
        skill.write_text("test workspace")
        video = version / "clip.mp4"
        video.write_bytes(b"synthetic media")
        (version / "clip.srt").write_text("caption")
        (version / "review.html").write_text("review")
        covers = []
        for ratio in ("3:4", "4:3", "16:9", "9:16"):
            filename = ratio.replace(":", "x") + ".png"
            (version / filename).write_bytes(b"fixture")
            covers.append({"path": filename, "ratio": ratio})
        worker.save_json(version / "package.json", {"video": "clip.mp4", "srt": "clip.srt", "covers": covers})
        rows = {}
        for platform in worker.PLATFORMS:
            item = self.row(platform)
            item["video_sha256"] = worker.digest(video)
            for step in ("save", "restore"):
                path = Path(item[step]["path"])
                shutil.copyfile(self.root / path, fixture / path)
            rows[platform] = item
        worker.save_json(self.root / "fixture-result.json", {"outcome": "edited", "package": "v1/package.json",
                         "review": "v1/review.html", "platforms": rows})
        cli = self.root / "fixture-codex"
        cli.write_text("""#!/bin/sh
cat >/dev/null
echo run >> calls
while [ "$1" != "--output-last-message" ]; do shift; done
echo '{"type":"turn.started"}'
cp -R fixture/. output/rec_42/
cp fixture-result.json "$2"
echo '{"type":"turn.completed"}'
""")
        cli.chmod(0o700)
        source = self.root / "rec_42.MP4"
        source.write_bytes(b"source")
        support = self.root / "runtime"
        command = [sys.executable, "-I", str(SCRIPT), "--workspace", str(self.root),
                   "--codex", str(cli), "--support", str(support), "--model", "test-model",
                   "--effort", "low", "--id", "test-run", "--language", "en", "--source"]
        subprocess.run(command + [str(source)], check=True, timeout=10)
        result = worker.read_json(support / "latest.json")
        self.assertEqual(result["phase"], "completed")
        self.assertTrue(all(row["status"] == "saved_verified" for row in result["platforms"]))
        renamed = self.root / "IMG_9.MOV"
        source.rename(renamed)
        subprocess.run(command + [str(renamed)], check=True, timeout=10)
        self.assertEqual(worker.read_json(support / "latest.json")["phase"], "noClip")
        self.assertEqual((self.root / "calls").read_text().splitlines(), ["run"])

    def test_progress_requires_a_new_artifact(self):
        job = self.root / "publish"
        job.mkdir()
        worker.save_json(job / "publication.json", {"events": [{"platform": "douyin"}]})
        stamp, stage = worker.artifact_activity(self.root, 0)
        self.assertEqual(stage, "drafting.douyin")
        self.assertEqual(worker.artifact_activity(self.root, stamp), (stamp, None))


if __name__ == "__main__":
    unittest.main()
