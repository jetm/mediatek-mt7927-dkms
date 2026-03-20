#!/usr/bin/env bash
# Build an .rpm package for mediatek-mt7927-dkms.
# Usage: ./build-rpm.sh
#
# Prerequisites: rpmbuild, make, python3, curl

set -euo pipefail

SPEC="mediatek-mt7927-dkms.spec"
VERSION=$(sed -n "s/^PACKAGE_VERSION=\"\(.*\)\"/\1/p" dkms.conf)
TOPDIR="${PWD}/rpmbuild"

if ! command -v rpmbuild &>/dev/null; then
    echo >&2 "rpmbuild not found. Install rpm-build:"
    echo >&2 "  Fedora: sudo dnf install rpm-build"
    exit 1
fi

echo "==> Building mediatek-mt7927-dkms ${VERSION} .rpm"

# Create rpmbuild tree
mkdir -p "${TOPDIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Create source tarball from current repo
TARNAME="mediatek-mt7927-dkms-${VERSION}"
git archive --format=tar.gz --prefix="${TARNAME}/" HEAD \
    -o "${TOPDIR}/SOURCES/${TARNAME}.tar.gz"

# Copy spec
cp "${SPEC}" "${TOPDIR}/SPECS/"

# Build
rpmbuild --define "_topdir ${TOPDIR}" --nodeps -bb "${TOPDIR}/SPECS/${SPEC}"

echo "==> RPMs:"
find "${TOPDIR}/RPMS" -name '*.rpm' -print
