# Each top-level directory with test/environments is a self-contained library.
LIBS := $(patsubst %/test/environments,%,$(wildcard */test/environments))

.PHONY: test fmt $(LIBS)
test: $(LIBS)

$(LIBS):
	$(MAKE) -C $@ test

fmt:
	find . -name '*.libsonnet' -o -name '*.jsonnet' | xargs jsonnetfmt -i
