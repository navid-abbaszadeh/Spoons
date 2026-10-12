# Spoons live in Source/<Name>.spoon. Targets:
#   make test   run each Spoon's unit tests (plain Lua 5.4+, no Hammerspoon needed)
#   make docs   regenerate each Spoon's docs.json and the combined docs/docs.json that
#               SpoonInstall reads (needs Hammerspoon running and its `hs` command)
#   make zip    build Spoons/<Name>.spoon.zip, which SpoonInstall downloads (tests left out)
#   make all    all of the above, before a release
SPOONS := $(wildcard Source/*.spoon)
NAMES := $(notdir $(SPOONS))

.PHONY: all test docs zip

all: test docs zip

test:
	@for s in $(SPOONS); do \
		if [ -f $$s/tests/run.lua ]; then echo "== $$s"; lua $$s/tests/run.lua || exit 1; fi; \
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
