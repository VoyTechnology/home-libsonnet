RTK ?= rustanka

# Every directory under test/environments is a Tanka environment that must render.
ENVS := $(wildcard test/environments/*)

.PHONY: test $(ENVS)
test: $(ENVS)

$(ENVS):
	@echo "rtk show $@"
	@$(RTK) show $@ --dangerous-allow-redirect > /dev/null
