from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


class DeploymentAssetsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.server = Path(__file__).parents[1]
        cls.root = cls.server.parent

    def test_production_installer_has_a_side_effect_free_dry_run(self) -> None:
        installer = self.server / "install-production.sh"
        syntax = subprocess.run(
            ["sh", "-n", str(installer)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(syntax.returncode, 0, syntax.stderr)

        result = subprocess.run(
            ["sh", str(installer), "--dry-run"],
            cwd=self.root,
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("No files, secrets, packages, or services", result.stdout)
        self.assertNotIn("password-pepper", result.stdout)

    def test_legacy_installer_is_explicitly_not_for_public_service(self) -> None:
        legacy = (self.server / "install.sh").read_text()
        self.assertIn("Legacy shared-token installer", legacy)
        self.assertIn("do not expose this service publicly", legacy)

    def test_systemd_profiles_bound_memory_and_schedule_verified_backup(self) -> None:
        api = (
            self.server / "systemd/comicollect-production.service"
        ).read_text()
        backup = (
            self.server / "systemd/comicollect-production-backup.service"
        ).read_text()
        check = (
            self.server / "systemd/comicollect-production-check.service"
        ).read_text()
        timer = (
            self.server / "systemd/comicollect-production-backup.timer"
        ).read_text()

        self.assertIn("MemoryHigh=512M", api)
        self.assertIn("MemoryMax=768M", api)
        self.assertIn("comicollect_wsgi --check", check)
        self.assertIn("EnvironmentFile=/etc/comicollect/production.env", check)
        self.assertIn("--mode production --backup", backup)
        self.assertIn("EnvironmentFile=/etc/comicollect/production.env", backup)
        self.assertIn("MemoryMax=384M", backup)
        self.assertIn("Persistent=true", timer)
        self.assertIn("comicollect-production-backup.service", timer)

    def test_installer_checks_new_release_before_explicit_restart(self) -> None:
        installer = (self.server / "install-production.sh").read_text()
        check = "systemctl start comicollect-production-check.service"
        restart = "systemctl restart comicollect-production.service"

        self.assertIn(check, installer)
        self.assertIn(restart, installer)
        self.assertLess(installer.index(check), installer.index(restart))
        self.assertNotIn("enable --now", installer)
        self.assertIn(
            '"$SERVER_DIR/deploy/nginx/comicollect.conf"',
            installer,
        )

    def test_legacy_units_always_select_legacy_mode(self) -> None:
        api = (self.server / "systemd/comicollect.service").read_text()
        backup = (
            self.server / "systemd/comicollect-backup.service"
        ).read_text()

        self.assertIn("comicollect_server.py --mode legacy", api)
        self.assertIn(
            "comicollect_server.py --mode legacy --backup",
            backup,
        )

    def test_nginx_access_format_uses_path_without_query_string(self) -> None:
        nginx = (self.server / "deploy/nginx/comicollect.conf").read_text()
        start = nginx.index("log_format comicollect_no_query")
        end = nginx.index(";", start)
        access_format = nginx[start:end]

        self.assertIn("$request_method $uri $server_protocol", access_format)
        self.assertNotIn("$request_uri", access_format)
        self.assertNotIn("$args", access_format)
        self.assertIn("comicollect-access.log comicollect_no_query", nginx)
        self.assertIn("zone=comicollect_login", nginx)
        self.assertIn("zone=comicollect_session", nginx)
        self.assertIn("location = /api/v1/sync", nginx)
        self.assertIn("client_max_body_size 1m", nginx)

    def test_runtime_dependency_is_exactly_pinned(self) -> None:
        requirements = [
            line.strip()
            for line in (
                self.server / "requirements-production.txt"
            ).read_text().splitlines()
            if line.strip() and not line.lstrip().startswith("#")
        ]
        self.assertEqual(requirements, ["gunicorn==26.0.0"])


if __name__ == "__main__":
    unittest.main()
