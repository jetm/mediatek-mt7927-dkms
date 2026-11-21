from pathlib import Path
import re
import unittest

PKGBUILD = Path(__file__).resolve().parents[1] / 'PKGBUILD'

# The Makefile re-runs the staging recipe on every `make install` because
# check-version is a .PHONY prerequisite of the stamp. package() therefore needs
# the same inputs build() passes, or it falls back to a tarball and ZIP in the
# startdir, which only exist when makepkg's SRCDEST is the startdir.
STAGING_INPUTS = ('MT76_KVER', 'KERNEL_TARBALL', 'DRIVER_ZIP', 'SRCDIR')


def make_call(text, function, target):
    body = re.search(r'^%s\(\) \{\n(.*?)^\}' % function, text, re.S | re.M)
    assert body, f'{function}() not found in PKGBUILD'
    call = re.search(r'make -C "\$\{startdir\}" %s\b(.*?)(?=\n\S|\n\}|\Z)' % target, body.group(1), re.S)
    assert call, f'no `make {target}` call in {function}()'
    return call.group(1)


class SrcdestIndependence(unittest.TestCase):
    def test_build_and_package_pass_the_staging_inputs(self):
        text = PKGBUILD.read_text()
        for function, target in (('build', 'sources'), ('package', 'install')):
            call = make_call(text, function, target)
            for name in STAGING_INPUTS:
                with self.subTest(function=function, variable=name):
                    self.assertIn(f'{name}=', call)

    def test_package_uses_the_same_tarball_and_zip_as_build(self):
        text = PKGBUILD.read_text()
        build = make_call(text, 'build', 'sources')
        package = make_call(text, 'package', 'install')
        for name in ('KERNEL_TARBALL', 'DRIVER_ZIP'):
            with self.subTest(variable=name):
                want = re.search(r'%s="([^"]*)"' % name, build)
                got = re.search(r'%s="([^"]*)"' % name, package)
                self.assertTrue(want and got)
                self.assertEqual(want.group(1), got.group(1))


if __name__ == '__main__':
    unittest.main()
