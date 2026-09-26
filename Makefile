NASM ?= nasm
DOSBOX ?= dosbox
GAME_DIR ?=
DOSBOX_LIB_DIR ?=

.PHONY: all clean test audit emutest verify dist

all: build/JP2GUS.COM

build/JP2GUS.COM: src/jp2gus.asm
	mkdir -p build
	$(NASM) -f bin -Wall -Werror -o $@ $<

test: all
	$(if $(GAME_DIR),JP2_GAME_DIR="$(GAME_DIR)") python3 -m unittest discover -s tests -v

audit:
	python3 tools/audit_repository.py $(if $(GAME_DIR),--reference-dir "$(GAME_DIR)",)

emutest: all
	test -n "$(GAME_DIR)" || (echo 'set GAME_DIR to the original game directory' >&2; exit 2)
	python3 tools/run_emulator_tests.py --game-dir "$(GAME_DIR)" --dosbox "$(DOSBOX)" $(if $(DOSBOX_LIB_DIR),--library-dir "$(DOSBOX_LIB_DIR)",)

verify: test audit emutest

dist: all audit
	python3 tools/package_release.py

clean:
	rm -rf build dist test-work
