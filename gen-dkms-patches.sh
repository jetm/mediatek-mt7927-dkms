#!/usr/bin/env bash
set -euo pipefail

# Generate DKMS WiFi patches from kernel tree commits.
#
# Creates a temp git repo from the kernel tarball + mt7902 patch, then applies
# each kernel commit's diff sequentially. The resulting diffs have exact line
# numbers for the DKMS build context (kernel.org + mt7902 + preceding patches).
#
# Usage:
#   ./gen-dkms-patches.sh              # regenerate all
#   ./gen-dkms-patches.sh 14           # regenerate just patch #14
#   ./gen-dkms-patches.sh 14 16 18     # regenerate specific patches
#   ./gen-dkms-patches.sh --dry-run    # verify patches apply, don't write

DKMS_DIR="$(cd "$(dirname "$0")" && pwd)"
KERNEL_TREE="${KERNEL_TREE:-$HOME/repos/personal/linux-stable}"
KERNEL_BRANCH="${KERNEL_BRANCH:-mt7927-wifi-dkms}"
MT76_SUBDIR="drivers/net/wireless/mediatek/mt76"

# Parse arguments
dry_run=false
patches_to_gen=()
for arg in "$@"; do
	case "$arg" in
		--dry-run) dry_run=true ;;
		*) patches_to_gen+=("$arg") ;;
	esac
done

# Read kernel version tag from PKGBUILD
mt76_kver=$(grep '^_mt76_kver=' "$DKMS_DIR/PKGBUILD" | cut -d"'" -f2)
base_tag="v${mt76_kver}"
tarball="$DKMS_DIR/linux-${mt76_kver}.tar.xz"

if [[ ! -f "$tarball" ]]; then
	echo "ERROR: Tarball $tarball not found"
	echo "Download it or run makepkg --nobuild to fetch sources first."
	exit 1
fi

# Get ordered commit list from kernel branch
mapfile -t commits < <(
	git -C "$KERNEL_TREE" log --reverse --format='%H' \
		"$KERNEL_BRANCH" --not "$base_tag"
)

if (( ${#commits[@]} == 0 )); then
	echo "No commits found on $KERNEL_BRANCH above $base_tag"
	exit 1
fi

echo "Found ${#commits[@]} commits on $KERNEL_BRANCH (base: $base_tag)"

# Build subject-to-filename mapping from existing patches
declare -A subject_to_file
for patchfile in "$DKMS_DIR"/mt7927-wifi-*.patch; do
	[[ -f "$patchfile" ]] || continue
	subject=$(head -1 "$patchfile")
	subject_to_file["$subject"]="$(basename "$patchfile")"
done

# Create temp workspace with git-tracked mt76 source
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

echo "Extracting mt76 from kernel v${mt76_kver}..."
mkdir -p "$work/mt76"
tar -xf "$tarball" --strip-components=6 -C "$work/mt76" \
	"linux-${mt76_kver}/${MT76_SUBDIR}"

cd "$work/mt76"
git init -q
git config user.email "$(git -C "$KERNEL_TREE" config user.email)"
git config user.name "$(git -C "$KERNEL_TREE" config user.name)"
git add -A
git commit -q -m "kernel.org v${mt76_kver}"

# Apply mt7902 patch to establish shifted baseline
patch -p1 --quiet < "$DKMS_DIR/mt7902-wifi-6.19.patch"
git add -A
git commit -q -m "mt7902"

echo "Generating patches..."

errors=0

for i in "${!commits[@]}"; do
	n=$((i + 1))
	nn=$(printf '%02d' "$n")
	commit=${commits[$i]}

	# Get commit info from kernel tree
	subject=$(git -C "$KERNEL_TREE" log -1 --format='%s' "$commit")
	body=$(git -C "$KERNEL_TREE" log -1 --format='%B' "$commit")

	# Extract diff from kernel tree, strip mt76 path prefix
	kernel_diff=$(git -C "$KERNEL_TREE" diff -U1 "${commit}^..$commit" \
		-- "$MT76_SUBDIR/" | \
		sed "s|a/${MT76_SUBDIR}/|a/|g; s|b/${MT76_SUBDIR}/|b/|g")

	if [[ -z "$kernel_diff" ]]; then
		echo "  WARNING: [$nn] ($subject) empty diff - skipping"
		continue
	fi

	# Apply to temp tree (which has mt7902 + preceding patches)
	cd "$work/mt76"
	if ! echo "$kernel_diff" | git apply --quiet 2>/dev/null; then
		if ! echo "$kernel_diff" | git apply --3way --quiet 2>/dev/null; then
			echo "  FAIL: [$nn] $subject"
			errors=$((errors + 1))
			continue
		fi
	fi
	git add -A
	git commit -q -m "$subject"

	# Capture diff from the temp repo - these line numbers are exact
	dkms_diff=$(git diff -U1 HEAD~1..HEAD)

	# Find existing patch file or generate new name
	if [[ -n "${subject_to_file[$subject]:-}" ]]; then
		outfile="${subject_to_file[$subject]}"
	else
		slug=$(echo "$subject" | \
			sed 's/wifi: mt76: mt7925: //' | \
			tr '[:upper:]' '[:lower:]' | \
			tr ' ' '-' | \
			sed 's/[^a-z0-9-]//g' | \
			cut -c1-40 | \
			sed 's/-$//')
		outfile="mt7927-wifi-${nn}-${slug}.patch"
	fi

	# Filter to specific patches if requested
	if (( ${#patches_to_gen[@]} > 0 )); then
		skip=true
		for p in "${patches_to_gen[@]}"; do
			if (( p == n )); then skip=false; break; fi
		done
		$skip && continue
	fi

	if $dry_run; then
		echo "  [$nn/${#commits[@]}] $outfile (OK)"
		continue
	fi

	# Write patch: commit message + SHA + diff
	{
		echo -n "$body" | sed -e :a -e '/^\n*$/{$d;N;ba}'
		echo ""
		echo ""
		echo "$commit"
		echo "$dkms_diff"
	} > "$DKMS_DIR/$outfile"

	echo "  [$nn/${#commits[@]}] $outfile"
done

if (( errors > 0 )); then
	echo "FAILED: $errors patch(es) could not be applied"
	exit 1
fi

echo "Done."
