# Each top-level directory with a test/ folder is a self-contained library.
LIBS := $(patsubst %/test,%,$(wildcard */test))

.PHONY: test fmt $(LIBS)
test: $(LIBS)

$(LIBS):
	$(MAKE) -C $@ test

fmt:
	find . -name '*.libsonnet' -o -name '*.jsonnet' | xargs jsonnetfmt -i
