# Same contribution contract as ristretto-ai: `make check` is the single
# entry point for everything CI runs.
.PHONY: check test

check:
	bash scripts/check.sh

test:
	@fail=0; for t in plugins/harness/test/*.test.sh; do echo "== $$t"; bash $$t || fail=1; done; exit $$fail
