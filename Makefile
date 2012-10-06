# OASIS_START
# DO NOT EDIT (digest: bc1e05bfc8b39b664f29dae8dbd3ebbb)

SETUP = ocaml setup.ml

build: setup.data
	$(SETUP) -build $(BUILDFLAGS)

doc: setup.data build
	$(SETUP) -doc $(DOCFLAGS)

test: setup.data build
	$(SETUP) -test $(TESTFLAGS)

all: 
	$(SETUP) -all $(ALLFLAGS)

install: setup.data
	$(SETUP) -install $(INSTALLFLAGS)

uninstall: setup.data
	$(SETUP) -uninstall $(UNINSTALLFLAGS)

reinstall: setup.data
	$(SETUP) -reinstall $(REINSTALLFLAGS)

clean: 
	$(SETUP) -clean $(CLEANFLAGS)

distclean: 
	$(SETUP) -distclean $(DISTCLEANFLAGS)

setup.data:
	$(SETUP) -configure $(CONFIGUREFLAGS)

.PHONY: build doc test all install uninstall reinstall clean distclean configure

# OASIS_STOP

run: install-data
	CAML_LD_LIBRARY_PATH=_build/src/core ocsigenserver -c local/etc/ocsigen/ocsimore.conf -v

restart: install-data
	echo restart > /tmp/cpipe

.PHONY:
install-data: /tmp/static
	cp \
	   ./local/var/www/static/*.css \
	   ./local/var/www/static/*.png \
	   ./_build/src/site/client/ocsimore.js \
	   $^

/tmp/static:
	mkdir $@

/tmp/static/css:
	mkdir $@
