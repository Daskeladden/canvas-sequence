# canvas-sequence -- sequence diagrams on an Emacs 32 canvas,
# built on canvas-diagram.

EMACS   ?= emacs
DIAGRAM ?= ../canvas-diagram
SOURCES  = $(wildcard canvas-sequence*.el)
TESTS    = $(wildcard tests/canvas-sequence*-tests.el)

.PHONY: test compile build module clean

test: module
	$(EMACS) -Q --batch -L . -L $(DIAGRAM) -L tests \
	  $(foreach t,$(TESTS),-l $(t)) \
	  --eval '(ert-run-tests-batch-and-exit)'

# Every file byte-compiles with no warning.  The .elc files go again at
# once, so that the tests never load old compiled code.
compile: module
	$(EMACS) -Q --batch -L . -L $(DIAGRAM) \
	  --eval '(setq byte-compile-error-on-warn t)' \
	  -f batch-byte-compile $(SOURCES); \
	status=$$?; rm -f *.elc; exit $$status

# Byte-compile and keep the .elc files.  Set `load-prefer-newer' to t if
# you keep them, so that Emacs never loads compiled code older than its
# source.
build: module
	$(EMACS) -Q --batch -L . -L $(DIAGRAM) -f batch-byte-compile $(SOURCES)

# The cairo and pango module lives with canvas-diagram.
module:
	$(MAKE) -C $(DIAGRAM)

clean:
	rm -f *.elc tests/*.elc
