from __future__ import annotations

import os
import runpy
import subprocess
import unittest
from pathlib import Path
from unittest.mock import patch


class _HealthyResponse:
    status = 200

    class Headers:
        @staticmethod
        def get_content_type() -> str:
            return "application/json"

    headers = Headers()

    def __enter__(self):
        return self

    def __exit__(self, *args: object) -> None:
        return None

    @staticmethod
    def read(maximum: int) -> bytes:
        return b'{"ok":true}'


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
        helper = self.server / "deploy/production-release.sh"
        helper_syntax = subprocess.run(
            ["sh", "-n", str(helper)],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(helper_syntax.returncode, 0, helper_syntax.stderr)

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
            self.server / "systemd/comicollect-production-check@.service"
        ).read_text()
        timer = (
            self.server / "systemd/comicollect-production-backup.timer"
        ).read_text()

        self.assertIn("MemoryHigh=512M", api)
        self.assertIn("MemoryMax=768M", api)
        self.assertIn("releases/%i", check)
        self.assertIn("comicollect_wsgi --check", check)
        self.assertIn("snapshot-if-present", check)
        self.assertIn("EnvironmentFile=/etc/comicollect/production.env", check)
        self.assertIn(
            "RequiresMountsFor=/var/lib/comicollect /var/backups/comicollect",
            check,
        )
        self.assertIn("-m comicollect_backup create", backup)
        self.assertIn("/opt/comicollect/current/", backup)
        self.assertIn("EnvironmentFile=/etc/comicollect/production.env", backup)
        self.assertIn(
            "RequiresMountsFor=/var/lib/comicollect /var/backups/comicollect",
            backup,
        )
        self.assertIn("MemoryMax=384M", backup)
        self.assertIn("/opt/comicollect/current/", api)
        self.assertIn(
            "ExecStartPost=/usr/bin/python3 "
            "/opt/comicollect/tools/production-healthcheck.py",
            api,
        )
        self.assertIn("Persistent=true", timer)
        self.assertIn("comicollect-production-backup.service", timer)

    def test_installer_activates_checked_immutable_release_with_rollback(self) -> None:
        installer_path = self.server / "install-production.sh"
        installer = installer_path.read_text()
        release = (self.server / "deploy/production-release.sh").read_text()

        self.assertEqual(installer_path.stat().st_mode & 0o111, 0o111)
        self.assertIn("RELEASES_DIR=$APP_ROOT/releases", installer)
        self.assertIn("production-release.sh", installer)
        self.assertIn("comicollect-production-install.lock", installer)
        self.assertIn("Refusing to replace a missing pepper", installer)
        saved_umask = "PEPPER_UMASK=$(umask)"
        secure_umask = "umask 077"
        restored_umask = 'umask "$PEPPER_UMASK"'
        self.assertLess(installer.index(saved_umask), installer.index(secure_umask))
        self.assertLess(installer.index(secure_umask), installer.index(restored_umask))
        self.assertLess(
            installer.index(restored_umask),
            installer.index("production-release.sh\" \"$SCRIPT_DIR\""),
        )
        self.assertNotIn("$SERVER_DIR/comicollect_server.py", installer)
        self.assertIn('python3 -m venv "$CANDIDATE/venv"', release)
        self.assertIn('remember_unit "$CHECK_TEMPLATE"', release)
        check = 'systemctl start "comicollect-production-check@$RELEASE_ID.service"'
        switch = 'atomic_current "$CANDIDATE"'
        restart = 'systemctl restart "$API_UNIT"'
        self.assertLess(release.index(check), release.index(switch))
        self.assertGreater(
            release.index(restart, release.index(switch)),
            release.index(switch),
        )
        self.assertIn('mv -Tf "$temporary" "$CURRENT_LINK"', release)
        self.assertIn('atomic_current "$PREVIOUS_TARGET"', release)
        self.assertIn("restoring the previous runtime", release)
        self.assertIn('systemctl stop "$TIMER_UNIT"', release)
        self.assertIn("backup is still active", release)
        self.assertIn('rm -f "$UNIT_DIR/$LEGACY_CHECK_UNIT"', release)
        self.assertIn('"$CANDIDATE/.activated"', release)
        self.assertIn('kept=1', release)

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

    def test_operator_docs_use_immutable_runtime_and_atomic_restore(self) -> None:
        auth = (self.root / "docs/backend-auth.md").read_text()
        deployment = (self.root / "docs/production-deployment.md").read_text()

        self.assertNotIn("/opt/comicollect/server", auth)
        self.assertNotIn("/opt/comicollect/venv", auth)
        self.assertIn("cd /opt/comicollect/current/server", auth)
        self.assertIn("exec ../venv/bin/python", auth)
        self.assertIn("cd /opt/comicollect/current/server", deployment)
        self.assertIn("restore_stage=/var/lib/comicollect.restore-", deployment)
        self.assertIn("preserved=/var/lib/comicollect.pre-restore-", deployment)
        self.assertIn(
            'sudo mv -T /var/lib/comicollect "$preserved"',
            deployment,
        )
        self.assertIn(
            'sudo mv -T "$restore_stage" /var/lib/comicollect',
            deployment,
        )
        self.assertNotIn(
            "# Preserve and restore the complete data directory here.",
            deployment,
        )

    def test_startup_healthcheck_requires_both_loopback_probes(self) -> None:
        script = runpy.run_path(
            str(self.server / "deploy/production-healthcheck.py"),
            run_name="production_healthcheck_test",
        )
        urls: list[str] = []

        def healthy(request, timeout: float):
            urls.append(request.full_url)
            return _HealthyResponse()

        with patch.dict(os.environ, {"COMICOLLECT_PORT": "9876"}), patch(
            "urllib.request.urlopen",
            side_effect=healthy,
        ):
            self.assertEqual(script["main"](), 0)

        self.assertEqual(
            urls,
            [
                "http://127.0.0.1:9876/health/live",
                "http://127.0.0.1:9876/health/ready",
            ],
        )


if __name__ == "__main__":
    unittest.main()
