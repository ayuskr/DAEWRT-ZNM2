cp Scripts/Packages.sh Scripts/Packages.sh.bak
cat > Scripts/Packages.sh <<'EOF'
#!/bin/bash

set -e

export GIT_TERMINAL_PROMPT=0

UPDATE_PACKAGE() {
	local PKG_NAME="$1"
	local PKG_REPO="$2"
	local PKG_BRANCH="$3"
	local PKG_SPECIAL="${4:-}"
	local PKG_EXTRA_NAMES="${5:-}"
	local PKG_REQUIRED="${6:-true}"

	local REPO_NAME="${PKG_REPO#*/}"
	local SOURCE_DIR=".source-${REPO_NAME}"
	local REPO_URL="https://github.com/${PKG_REPO}.git"
	local PKG_LIST=("$PKG_NAME")

	if [ -n "$PKG_EXTRA_NAMES" ]; then
		local EXTRA_NAMES
		read -r -a EXTRA_NAMES <<< "$PKG_EXTRA_NAMES"
		PKG_LIST+=("${EXTRA_NAMES[@]}")
	fi

	echo
	echo "Preparing package: $PKG_NAME"
	echo "Repository: $REPO_URL"
	echo "Branch: $PKG_BRANCH"

	if ! git ls-remote \
		--exit-code \
		--heads \
		"$REPO_URL" \
		"$PKG_BRANCH" >/dev/null 2>&1;
