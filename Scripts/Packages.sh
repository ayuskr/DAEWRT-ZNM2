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
	local REPO_URL="https://github.com/${PKG_REPO}.git"
	local PKG_LIST=("$PKG_NAME")
	local NAME
	local DIR
	local FOUND_DIRS
	local SOURCE_DIR
	local PACKAGE_DIR

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
		"$PKG_BRANCH" >/dev/null 2>&1; then

		if [ "$PKG_REQUIRED" = "true" ]; then
			echo "ERROR: Required repository or branch is unavailable."
			echo "Repository: $REPO_URL"
			echo "Branch: $PKG_BRANCH"
			exit 1
		fi

		echo "WARNING: Optional repository or branch is unavailable."
		echo "Repository: $REPO_URL"
		echo "Branch: $PKG_BRANCH"
		echo "Skipping optional package: $PKG_NAME"
		return 0
	fi

	for NAME in "${PKG_LIST[@]}"; do
		echo "Search directory: $NAME"

		FOUND_DIRS=$(find \
			../feeds/luci/ \
			../feeds/packages/ \
			-maxdepth 3 \
			-type d \
			-iname "*$NAME*" \
			2>/dev/null || true)

		if [ -n "$FOUND_DIRS" ]; then
			while IFS= read -r DIR; do
				[ -n "$DIR" ] || continue

				rm -rf "$DIR"
				echo "Delete directory: $DIR"
			done <<< "$FOUND_DIRS"
		else
			echo "Not found directory: $NAME"
		fi
	done

	if [ "$PKG_SPECIAL" = "pkg" ]; then
		SOURCE_DIR=$(mktemp -d "./.source-${REPO_NAME}.XXXXXX")

		git clone \
			--depth=1 \
			--single-branch \
			--branch "$PKG_BRANCH" \
			"$REPO_URL" \
			"$SOURCE_DIR"

		for NAME in "${PKG_LIST[@]}"; do
			PACKAGE_DIR=$(find "$SOURCE_DIR" \
				-mindepth 1 \
				-maxdepth 4 \
				-type d \
				-name "$NAME" \
				-print \
				-quit)

			if [ -z "$PACKAGE_DIR" ] || [ ! -f "$PACKAGE_DIR/Makefile" ]; then
				echo "ERROR: Package directory or Makefile not found: $NAME"
				rm -rf "$SOURCE_DIR"

				if [ "$PKG_REQUIRED" = "true" ]; then
					exit 1
				fi

				return 0
			fi

			rm -rf "./$NAME"
			cp -a "$PACKAGE_DIR" "./$NAME"

			echo "Copy package directory: $PACKAGE_DIR -> ./$NAME"
		done

		rm -rf "$SOURCE_DIR"

	elif [ "$PKG_SPECIAL" = "name" ]; then
		SOURCE_DIR=$(mktemp -d "./.source-${REPO_NAME}.XXXXXX")

		git clone \
			--depth=1 \
			--single-branch \
			--branch "$PKG_BRANCH" \
			"$REPO_URL" \
			"$SOURCE_DIR"

		if [ ! -f "$SOURCE_DIR/Makefile" ]; then
			echo "ERROR: Package Makefile not found in repository root:"
			echo "$PKG_REPO"
			rm -rf "$SOURCE_DIR"

			if [ "$PKG_REQUIRED" = "true" ]; then
				exit 1
			fi

			return 0
		fi

		rm -rf "./$PKG_NAME"
		mv "$SOURCE_DIR" "./$PKG_NAME"

		echo "Package directory prepared: ./$PKG_NAME"

	else
		rm -rf "$REPO_NAME"

		git clone \
			--depth=1 \
			--single-branch \
			--branch "$PKG_BRANCH" \
			"$REPO_URL" \
			"$REPO_NAME"

		echo "Repository directory prepared: ./$REPO_NAME"
	fi
}

PATCH_DAED_MAKEFILE() {
	local DAED_MAKEFILE="./luci-app-daed/daed/Makefile"
	local PREPARE_BLOCK

	if [ ! -f "$DAED_MAKEFILE" ]; then
		echo "ERROR: Daed Makefile not found:"
		echo "$DAED_MAKEFILE"
		exit 1
	fi

	if ! grep -q '^GO_PKG_TAGS:=embedallowed,trace$' "$DAED_MAKEFILE"; then
		echo "ERROR: Daed Web UI embedding is disabled."
		echo "Expected: GO_PKG_TAGS:=embedallowed,trace"
		exit 1
	fi

	if ! grep -q 'git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR)' \
		"$DAED_MAKEFILE"; then
		echo "ERROR: Expected dae-wing clone command was not found."
		exit 1
	fi

	if ! grep -q 'pnpm install ;' "$DAED_MAKEFILE"; then
		echo "ERROR: Expected pnpm install command was not found."
		exit 1
	fi

	if ! grep -q 'pnpm build --filter daed ;' "$DAED_MAKEFILE"; then
		echo "ERROR: Expected Daed frontend build command was not found."
		echo "Expected: pnpm build --filter daed ;"
		exit 1
	fi

	if ! grep -q 'apps/web/dist' "$DAED_MAKEFILE"; then
		echo "ERROR: Daed Makefile does not contain apps/web/dist."
		exit 1
	fi

	# Clean the target directory before cloning dae-wing.
	sed -i \
		's@\t\t\tgit clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR) && \\@\t\t\trm -rf $(PKG_BUILD_DIR) ; \\@' \
		"$DAED_MAKEFILE"

	sed -i \
		'/^[[:space:]]*rm -rf $(PKG_BUILD_DIR) ; \\$/a\
			git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR) \&\& \\' \
		"$DAED_MAKEFILE"

	# Disable pnpm frozen-lockfile mode.
	sed -i \
		's@\t\t\tpnpm install ; \\@\t\t\tpnpm install --no-frozen-lockfile ; \\@' \
		"$DAED_MAKEFILE"

	# Verify the Daed frontend output.
	sed -i \
		's@\t\t\tpnpm build --filter daed ; \\@\t\t\tpnpm build --filter daed ; \\\
			test -d apps/web/dist ; \\\
			find apps/web/dist -type f -print -quit | grep -q . ; \\@' \
		"$DAED_MAKEFILE"

	# Stop immediately if a Build/Prepare command fails.
	sed -i \
		'/^define Build\/Prepare$/,/^endef$/ s/^[[:space:]]*( \\$/\t( set -e; \\/' \
		"$DAED_MAKEFILE"

	PREPARE_BLOCK=$(sed -n \
		'/^define Build\/Prepare$/,/^endef$/p' \
		"$DAED_MAKEFILE")

	if ! grep -q 'rm -rf $(PKG_BUILD_DIR)' <<< "$PREPARE_BLOCK"; then
		echo "ERROR: Failed to add dae-wing directory cleanup."
		exit 1
	fi

	if ! grep -q 'git clone https://github.com/daeuniverse/dae-wing $(PKG_BUILD_DIR)' \
		<<< "$PREPARE_BLOCK"; then
		echo "ERROR: The dae-wing clone command was lost while patching."
		exit 1
	fi

	if ! grep -q 'pnpm install --no-frozen-lockfile' <<< "$PREPARE_BLOCK"; then
		echo "ERROR: Failed to disable pnpm frozen-lockfile."
		exit 1
	fi

	if ! grep -q 'pnpm build --filter daed' <<< "$PREPARE_BLOCK"; then
		echo "ERROR: The Daed frontend build command was lost."
		exit 1
	fi

	if ! grep -q 'find apps/web/dist -type f -print -quit | grep -q .' \
		<<< "$PREPARE_BLOCK"; then
		echo "ERROR: Failed to add the Daed frontend output check."
		exit 1
	fi

	if ! grep -q 'set -e;' <<< "$PREPARE_BLOCK"; then
		echo "ERROR: Failed to enable error checking in Build/Prepare."
		exit 1
	fi

	echo "Daed Makefile patched successfully."
	echo "Web UI embedding: enabled"
	echo "Frontend build command: pnpm build --filter daed"
	echo "PNPM lockfile mode: no-frozen-lockfile"
	echo "Frontend output check: enabled"
}

# Remove potentially conflicting packages.
rm -rf ../feeds/luci/applications/luci-app-passwall*
rm -rf ../feeds/luci/applications/luci-app-mosdns*
rm -rf ../feeds/luci/applications/luci-app-dockerman*
rm -rf ../feeds/luci/applications/luci-app-dae*
rm -rf ../feeds/luci/applications/luci-app-bypass*
rm -rf ../feeds/packages/net/dae*

# Remove old theme packages.
rm -rf ../feeds/luci/themes/luci-theme-argon
rm -rf ../feeds/luci/themes/luci-theme-aurora
rm -rf ../feeds/luci/themes/luci-theme-glass

# Daed
UPDATE_PACKAGE \
	"luci-app-daed" \
	"QiuSimons/luci-app-daed" \
	"kix" \
	"" \
	"" \
	"true"

PATCH_DAED_MAKEFILE

# Lucky
UPDATE_PACKAGE \
	"luci-app-lucky" \
	"gdy666/luci-app-lucky" \
	"main" \
	"" \
	"lucky" \
	"true"

# Glass
UPDATE_PACKAGE \
	"luci-theme-glass" \
	"rchen14b/luci-theme-glass" \
	"main" \
	"" \
	"glass" \
	"true"

# Vantage theme and companion application.
UPDATE_PACKAGE \
	"luci-theme-vantage" \
	"anothaDev/luci-theme-vantage" \
	"main" \
	"pkg" \
	"luci-app-vantage" \
	"true"

# Material Design 3
UPDATE_PACKAGE \
	"luci-theme-material3" \
	"KawaiiHachimi/luci-theme-material3" \
	"main" \
	"name" \
	"" \
	"true"

# Check that the theme packages exist before continuing.
for REQUIRED_PACKAGE in \
	"luci-theme-vantage" \
	"luci-app-vantage" \
	"luci-theme-material3"; do

	if [ ! -f "./$REQUIRED_PACKAGE/Makefile" ]; then
		echo "ERROR: Required package Makefile is missing:"
		echo "./$REQUIRED_PACKAGE/Makefile"
		exit 1
	fi

	echo "Verified package: $REQUIRED_PACKAGE"
done

echo "Custom theme package verification completed successfully."
