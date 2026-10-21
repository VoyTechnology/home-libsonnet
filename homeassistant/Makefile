.PHONY: test
test:
	@for t in test/*_test.jsonnet; do \
		echo "jsonnet $$t"; \
		jsonnet -J . $$t > /dev/null || exit 1; \
	done
