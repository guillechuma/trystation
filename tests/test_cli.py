import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts" / "trystation.py"


class TryStationCliTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.base = Path(self.temp.name)
        self.tries = self.base / "tries"
        self.state = self.base / "state"
        self.env = {**os.environ, "XDG_STATE_HOME": str(self.state)}

    def tearDown(self):
        self.temp.cleanup()

    def run_cli(self, *args):
        return subprocess.run(
            [str(CLI), *map(str, args)],
            env=self.env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=True,
        )

    def listing(self):
        result = self.run_cli("list", "--path", self.tries)
        return json.loads(result.stdout)

    def test_missing_directory_is_not_created_by_listing(self):
        result = self.listing()
        self.assertFalse(result["exists"])
        self.assertEqual(result["sessions"], [])
        self.assertFalse(self.tries.exists())

    def test_create_uses_try_compatible_date_prefix_and_collision_suffix(self):
        first = json.loads(self.run_cli("create", "--path", self.tries, "--name", "QML shader test").stdout)
        second = json.loads(self.run_cli("create", "--path", self.tries, "--name", "QML shader test").stdout)
        self.assertRegex(Path(first["path"]).name, r"^\d{4}-\d{2}-\d{2}-QML-shader-test$")
        self.assertTrue(Path(second["path"]).name.endswith("-2"))
        self.assertEqual(len(self.listing()["sessions"]), 2)

    def test_listing_reports_git_and_project_information(self):
        session = self.tries / "2026-08-12-widget-lab"
        session.mkdir(parents=True)
        (session / "package.json").write_text("{}")
        (session / "README.md").write_text("# Widget Lab\nA useful experiment.")
        subprocess.run(["git", "init", "-q", str(session)], check=True)
        result = self.listing()["sessions"][0]
        self.assertEqual(result["title"], "Widget Lab")
        self.assertEqual(result["language"], "JavaScript")
        self.assertTrue(result["git"])
        self.assertGreaterEqual(result["changes"], 2)
        self.assertIn("useful experiment", result["readme"])

    def test_metadata_is_external_and_follows_cli_rename(self):
        session = self.tries / "2026-08-12-first-name"
        session.mkdir(parents=True)
        self.run_cli(
            "set-meta", "--root", self.tries, "--session", session,
            "--group", "QML", "--note", "Try a shader", "--pinned", "true",
        )
        renamed = self.tries / "2026-08-12-renamed"
        session.rename(renamed)
        result = self.listing()["sessions"][0]
        self.assertEqual(result["group"], "QML")
        self.assertEqual(result["note"], "Try a shader")
        self.assertTrue(result["pinned"])
        self.assertFalse((renamed / ".trystation.json").exists())

    def test_pin_update_preserves_group_and_note(self):
        session = self.tries / "2026-08-12-pinned"
        session.mkdir(parents=True)
        self.run_cli(
            "set-meta", "--root", self.tries, "--session", session,
            "--group", "QML", "--note", "Keep this note",
        )
        self.run_cli(
            "set-pin", "--root", self.tries, "--session", session,
            "--pinned", "true",
        )
        pinned = self.listing()["sessions"][0]
        self.assertTrue(pinned["pinned"])
        self.assertEqual(pinned["group"], "QML")
        self.assertEqual(pinned["note"], "Keep this note")

        self.run_cli(
            "set-meta", "--root", self.tries, "--session", session,
            "--group", "Experiments", "--note", "Updated note",
        )
        details_updated = self.listing()["sessions"][0]
        self.assertTrue(details_updated["pinned"])
        self.assertEqual(details_updated["group"], "Experiments")
        self.assertEqual(details_updated["note"], "Updated note")

        self.run_cli(
            "set-pin", "--root", self.tries, "--session", session,
            "--pinned", "false",
        )
        unpinned = self.listing()["sessions"][0]
        self.assertFalse(unpinned["pinned"])
        self.assertEqual(unpinned["group"], "Experiments")
        self.assertEqual(unpinned["note"], "Updated note")

    def test_graduated_symlink_is_visible(self):
        self.tries.mkdir()
        project = self.base / "projects" / "graduated"
        project.mkdir(parents=True)
        link = self.tries / "2026-08-12-graduated"
        link.symlink_to(project, target_is_directory=True)
        result = self.listing()["sessions"][0]
        self.assertTrue(result["graduated"])
        self.assertEqual(result["target"], str(project))

    def test_mutations_refuse_paths_outside_the_try_directory(self):
        self.tries.mkdir()
        outside = self.base / "outside"
        outside.mkdir()

        commands = [
            ("set-meta", "--group", "Unsafe"),
            ("set-pin", "--pinned", "true"),
            ("trash",),
        ]
        for command in commands:
            with self.subTest(command=command[0]):
                with self.assertRaises(subprocess.CalledProcessError):
                    self.run_cli(
                        command[0], "--root", self.tries, "--session", outside,
                        *command[1:],
                    )

        self.assertTrue(outside.is_dir())
        self.assertFalse((self.state / "trystation" / "metadata.json").exists())

    def test_trashing_graduated_symlink_preserves_destination(self):
        self.tries.mkdir()
        project = self.base / "projects" / "graduated"
        project.mkdir(parents=True)
        marker = project / "keep.txt"
        marker.write_text("safe")
        link = self.tries / "2026-08-12-graduated"
        link.symlink_to(project, target_is_directory=True)
        self.run_cli(
            "set-meta", "--root", self.tries, "--session", link,
            "--group", "Graduated", "--note", "Keep the destination",
        )

        self.run_cli("trash", "--root", self.tries, "--session", link)

        self.assertFalse(link.exists())
        self.assertFalse(link.is_symlink())
        self.assertEqual(marker.read_text(), "safe")
        metadata = json.loads((self.state / "trystation" / "metadata.json").read_text())
        self.assertEqual(metadata, {})

    def test_trashing_regular_try_invokes_gio_trash(self):
        session = self.tries / "2026-08-12-trash-me"
        session.mkdir(parents=True)
        (session / "keep.txt").write_text("recoverable")

        fake_bin = self.base / "bin"
        fake_bin.mkdir()
        trash_dir = self.base / "fake-trash"
        log = self.base / "gio.log"
        gio = fake_bin / "gio"
        gio.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$@\" > \"$GIO_LOG\"\n"
            "test \"$1\" = trash || exit 64\n"
            "mkdir -p \"$FAKE_TRASH_DIR\"\n"
            "mv -- \"$2\" \"$FAKE_TRASH_DIR/\"\n"
        )
        gio.chmod(0o755)
        self.env.update({
            "PATH": f"{fake_bin}:{self.env['PATH']}",
            "GIO_LOG": str(log),
            "FAKE_TRASH_DIR": str(trash_dir),
        })

        self.run_cli("trash", "--root", self.tries, "--session", session)

        trashed = trash_dir / session.name
        self.assertFalse(session.exists())
        self.assertEqual((trashed / "keep.txt").read_text(), "recoverable")
        self.assertEqual(log.read_text().splitlines(), ["trash", str(session)])


if __name__ == "__main__":
    unittest.main()
