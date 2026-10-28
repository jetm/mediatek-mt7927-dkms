import os
from pathlib import Path
import subprocess
import unittest

DKMS_CONF = Path(__file__).resolve().parents[1] / 'dkms.conf'
OPT_IN = Path('/etc/mediatek-mt7927-dkms.conf')


def source_conf(kernelver=None):
    """Source dkms.conf the way a consumer does and return (rc, stderr, _bt_build).

    Arch's dkms pacman hook runs `source dkms.conf` in a subshell with no
    kernelver set, only to read BUILD_DEPENDS and BUILD_EXCLUSIVE_KERNEL. DKMS
    itself always provides kernelver.
    """
    env = {k: v for k, v in os.environ.items() if k != 'kernelver'}
    if kernelver is not None:
        env['kernelver'] = kernelver
    script = f'(source "{DKMS_CONF}" >/dev/null; rc=$?; echo "$rc"; echo "${{_bt_build}}")'
    proc = subprocess.run(['bash', '-c', script], env=env, capture_output=True, text=True, check=False)
    lines = proc.stdout.split('\n')
    return (int(lines[0]) if lines[0] else proc.returncode), proc.stderr, lines[1] if len(lines) > 1 else ''


class PacmanHookSourcing(unittest.TestCase):
    def test_unset_kernelver_does_not_abort(self):
        # 2.16-4 and 2.17-1 used ${kernelver:?}, which made the hook report
        # "Missing dependencies" and skip the build on Arch and CachyOS.
        rc, stderr, _ = source_conf(None)
        self.assertEqual(rc, 0, stderr)
        self.assertNotIn('kernelver', stderr)

    def test_empty_kernelver_does_not_abort(self):
        rc, stderr, _ = source_conf('')
        self.assertEqual(rc, 0, stderr)


@unittest.skipIf(OPT_IN.exists(), f'{OPT_IN} overrides the version gate on this host')
class BluetoothGate(unittest.TestCase):
    def test_gate_follows_kernel_version(self):
        for kernelver, bt in [
            ('6.8.0-138-generic', 'yes'),
            ('6.17.9', 'yes'),
            ('7.0.5-1', 'yes'),
            ('7.1.0', 'no'),
            ('7.3.0-5-cachyos', 'no'),
            ('8.0.0', 'no'),
        ]:
            with self.subTest(kernelver=kernelver):
                rc, stderr, got = source_conf(kernelver)
                self.assertEqual(rc, 0, stderr)
                self.assertEqual(got, bt)

    def test_unset_kernelver_keeps_bluetooth_on(self):
        _, _, got = source_conf(None)
        self.assertEqual(got, 'yes')


if __name__ == '__main__':
    unittest.main()
