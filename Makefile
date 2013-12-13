REBAR = rebar

.PHONY: compile deps ct check_plt dialyzer typer cleanplt clean

all: deps compile

compile: deps
	$(REBAR) compile

deps:
	$(REBAR) get-deps

clean: docclean
	$(REBAR) clean

ct:	all
	$(REBAR) ct skip_deps=true
	
APPS = kernel stdlib sasl erts ssl tools os_mon runtime_tools crypto inets \
       xmerl webtool snmp public_key mnesia eunit common_test syntax_tools compiler
REPO = sc_push
COMBO_PLT = $(HOME)/.$(REPO)_combo_dialyzer_plt

check_plt: $(COMBO_PLT)
	dialyzer --check_plt \
			 --plt $(COMBO_PLT) \
			 --apps $(APPS) \
             ebin deps/*/ebin

$(COMBO_PLT):
	dialyzer --build_plt --output_plt $(COMBO_PLT) --apps $(APPS) \
             ebin deps/*/ebin

dialyzer: compile $(COMBO_PLT)
	@echo
	@echo Use "'make check_plt'" to check PLT prior to using this target.
	@echo Use "'make build_plt'" to build PLT prior to using this target.
	@echo
	@sleep 1
	dialyzer -Wno_return --plt $(COMBO_PLT) -c ebin

typer: compile $(COMBO_PLT)
	typer --plt $(COMBO_PLT) -r ./src

cleanplt:
	@echo
	@echo "Are you sure? It takes significant amount of time to re-build."
	@echo Deleting $(COMBO_PLT) in 5 seconds.
	@echo
	sleep 5
	rm -f $(COMBO_PLT)

docclean:
	@rm -rf doc/*.html doc/edoc-info html/

distclean: clean
	$(REBAR) delete-deps
	@rm -rf logs .test
	@rm -rf doc/*.html doc/edoc-info html/

docs:
	$(REBAR) doc skip_deps=true

xref: all
	$(REBAR) xref skip_deps=true
