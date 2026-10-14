library := build/SOML.scptd
libraryMetadata := $(library)/Contents/Info.plist
libraries := $(HOME)/Library/Script Libraries
NODE ?= node
FIXTURE ?= all
SAMPLES ?=
export OSA_LIBRARY_PATH := $(CURDIR)/build
export FIXTURE SAMPLES libraries NODE
scriptTests := $(patsubst test/%.applescript,%,$(filter-out test/tagger.applescript test/native-scalars.applescript test/writer-security.applescript test/construction.applescript test/construction-spelling.applescript test/construction-unicode.applescript,$(wildcard test/*.applescript)))
javaScriptTests := $(filter-out test/conformance.js test/runner.js,$(wildcard test/*.js))
testTargets := conformance $(scriptTests) native-scalars security construction generated

.DELETE_ON_ERROR:

.PHONY: build test $(testTargets) bench install clean

build: $(libraryMetadata)
	@if [ ! -f "$(library)/Contents/Resources/Scripts/main.scpt" ] || [ ! -f "$(library)/Contents/Resources/SOML.sdef" ]; then sh scripts/build.sh; fi

$(libraryMetadata): source/SOML.applescript source/SOML.sdef source/Info.plist scripts/build.sh
	sh scripts/build.sh

test: $(testTargets)

conformance: build
	"$$NODE" --test test/conformance.js

$(scriptTests): %: build test/%.applescript
	osascript "test/$@.applescript"

native-scalars: build
	TZ=UTC osascript test/native-scalars.applescript UTC
	TZ=America/New_York osascript test/native-scalars.applescript America/New_York

security: build
	osascript test/writer-security.applescript

construction: build
	osascript test/construction.applescript
	osascript test/construction-spelling.applescript
	osascript test/construction-unicode.applescript

generated: build
	"$$NODE" --test $(javaScriptTests)

bench: build
	osascript bench/benchmark.applescript "$$FIXTURE" "$$SAMPLES"

install: build
	sh scripts/build.sh install "$$libraries"

clean:
	if [ -e build ] || [ -L build ]; then trash build; fi
