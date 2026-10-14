#!/bin/sh
set -eu

case "${1:-build}" in
	build)
		if [ -L build ]; then
			printf '%s\n' 'Refusing symlinked build directory: build' >&2
			exit 1
		fi
		plutil -lint source/Info.plist
		xmllint --nonet --noout source/SOML.sdef
		mkdir -p build
		stagingDirectory=$(mktemp -d build/.soml.XXXXXXXX)
		trap 'trash "$stagingDirectory"' EXIT
		trap 'exit 1' HUP INT TERM
		osacompile -l AppleScript -o "$stagingDirectory/SOML.scptd" source/SOML.applescript
		cp source/SOML.sdef "$stagingDirectory/SOML.scptd/Contents/Resources/SOML.sdef"
		cp source/Info.plist "$stagingDirectory/SOML.scptd/Contents/Info.plist"
		destination=build/SOML.scptd
		;;
	install)
		libraries=$2
		mkdir -p "$libraries"
		stagingDirectory=$(mktemp -d "$libraries/.soml.XXXXXXXX")
		trap 'trash "$stagingDirectory"' EXIT
		trap 'exit 1' HUP INT TERM
		cp -R build/SOML.scptd "$stagingDirectory/SOML.scptd"
		destination="$libraries/SOML.scptd"
		;;
	*)
		printf '%s\n' 'Usage: sh scripts/build.sh [build|install destination]' >&2
		exit 1
		;;
esac

# The old bundle is renamed aside instead of deleted, so a failed replacement restores it. A failed restore leaves it in the Trash and still exits 1.
if [ -e "$destination" ] || [ -L "$destination" ]; then
	mv "$destination" "$stagingDirectory/previous"
fi
if mv "$stagingDirectory/SOML.scptd" "$destination"; then
	exit 0
fi
if [ -e "$destination" ] || [ -L "$destination" ]; then
	trash "$destination"
fi
if [ -e "$stagingDirectory/previous" ]; then
	mv "$stagingDirectory/previous" "$destination" || :
fi
exit 1
