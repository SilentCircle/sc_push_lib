.PHONY: deps ct

REBAR=rebar

all: deps compile

compile: deps
	$(REBAR) compile

deps:
	$(REBAR) get-deps

clean: docclean
	$(REBAR) clean

ct:	all
	$(REBAR) ct skip_deps=true

dialyzer: compile
	@dialyzer -Wno_return -c ebin

docclean:
	@rm -rf doc/*.html doc/edoc-info html/

distclean: clean
	$(REBAR) delete-deps
	@rm -rf deps logs .test
	@rm -rf doc/*.html doc/edoc-info html/

docs:
	$(REBAR) doc skip_deps=true

xref: all
	$(REBAR) xref skip_deps=true
