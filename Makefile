# Spoons live in Source/<Name>.spoon. Targets:
#   make test   run each Spoon's unit tests (plain Lua 5.4+, no Hammerspoon needed)
#   make docs   regenerate each Spoon's docs.json and the combined docs/docs.json that
#               SpoonInstall reads (needs Hammerspoon running and its `hs` command)
#   make zip    build Spoons/<Name>.spoon.zip, which SpoonInstall downloads (tests left out)
#   make all    all of the above, before a release
#   make check  what CI runs: the tests, plus checks that each zip matches its source and
#               docs/docs.json lists every Spoon (catches a forgotten make zip / make docs)
SPOONS := $(wildcard Source/*.spoon)
NAMES := $(notdir $(SPOONS))
LUA ?= lua

.PHONY: all test docs zip check check-zip check-docs

all: test docs zip

test:
	@for s in $(SPOONS); do \
		if [ -f $$s/tests/run.lua ]; then echo "== $$s"; $(LUA) $$s/tests/run.lua || exit 1; fi; \
	done

docs:
	@for s in $(SPOONS); do \
		hs -c "local s = '$(CURDIR)/$$s'; local f = io.open(s .. '/docs.json', 'w'); f:write(require('hs.doc.builder').genJSON(s)); f:close()" </dev/null || exit 1; \
	done
	@jq -s 'add' $(addsuffix /docs.json,$(SPOONS)) > docs/docs.json
	@echo "docs/docs.json: $$(jq length docs/docs.json) Spoon(s)"

zip:
	@for n in $(NAMES); do \
		rm -f Spoons/$$n.zip; \
		(cd Source && zip -qr ../Spoons/$$n.zip $$n -x "$$n/tests/*" "*.DS_Store") || exit 1; \
		echo "Spoons/$$n.zip"; \
	done

check: test check-zip check-docs

# Compares contents, not bytes: zips store timestamps, so a rebuild never matches exactly
check-zip:
	@tmp=$$(mktemp -d); status=0; \
	for n in $(NAMES); do \
		if [ ! -f Spoons/$$n.zip ]; then echo "Spoons/$$n.zip is missing: run make zip"; status=1; continue; fi; \
		unzip -q Spoons/$$n.zip -d $$tmp; \
		if diff -r -x tests -x .DS_Store Source/$$n $$tmp/$$n; then echo "Spoons/$$n.zip matches its source"; \
		else echo "Spoons/$$n.zip is out of date: run make zip"; status=1; fi; \
	done; \
	rm -rf $$tmp; exit $$status

check-docs:
	@status=0; \
	for n in $(basename $(NAMES)); do \
		if jq -e --arg n $$n 'any(.[]; .name == $$n)' docs/docs.json >/dev/null; then echo "docs/docs.json lists $$n"; \
		else echo "docs/docs.json doesn't list $$n: run make docs"; status=1; fi; \
	done; \
	exit $$status
