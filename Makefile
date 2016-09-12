.PHONY: all compile doc clean test ct dialyzer dialyzer-build-plt typer \
		shell distclean update-deps clean-common-test-data clean-doc-data \
		rebuild stashdoc rebar_script_test

ERLFLAGS= -pa $(CURDIR)/.eunit \
		  -pa $(CURDIR)/ebin \
		  -pa $(CURDIR)/deps/*/ebin \
		  -pa $(CURDIR)/test

#
# Check for required packages
#
REQUIRED_PKGS := \
	erl \
	dialyzer

_ := $(foreach pkg,$(REQUIRED_PACKAGES),\
		$(if $(shell which $(pkg)),\
			$(error Missing required package $(pkg)),))

ERLANG_VER=$(shell erl -noinput -eval 'io:put_chars(erlang:system_info(system_version)),halt().')

APP := sc_push_lib
README_URL := https://code.silentcircle.org/projects/SCPS/repos/$(APP)
DEPS_PLT=$(CURDIR)/.deps_plt
DIALYZER_WARNINGS = -Wunmatched_returns -Werror_handling -Wrace_conditions
DIALYZER_APPS = erts kernel stdlib mnesia

#DIALYZER_APPS = kernel stdlib sasl erts ssl tools os_mon runtime_tools crypto inets \
#       xmerl webtool snmp public_key mnesia eunit common_test syntax_tools compiler

# Prefer local rebar, if present

ifneq (,$(wildcard ./rebar))
    REBAR_PGM = `pwd`/rebar
else
    REBAR_PGM = rebar
endif

REBAR = $(REBAR_PGM)
REBAR_VSN := $(shell $(REBAR) --version)

all: rebar_script_test deps compile dialyzer test

info:
	@echo 'Erlang/OTP system version: $(ERLANG_VER)'
	@echo '$(REBAR_VSN)'

compile: info
	$(REBAR) skip_deps=true compile

doc: clean-doc-data compile
	$(REBAR) skip_deps=true doc

stashdoc: clean-doc-data compile
	EDOWN_TARGET=stash EDOWN_TOP_LEVEL_README_URL=$(README_URL) $(REBAR) skip_deps=true doc

deps: info
	$(REBAR) get-deps
	$(REBAR) compile

update-deps: info
	$(REBAR) update-deps
	$(REBAR) compile

# The tests depend on libraries not needed for production.
# ct_deps.config is a supplementary config file containing
# the extra dependencies. See rebar.config.script for the
# usage andbehavior of REBAR_EXTRA_DEPS_CFG. Also see
# extra_tests/rebar_config_SUITE.erl.
ct: rebar_script_test
	$(REBAR) -C ct_deps.config get-deps
	REBAR_EXTRA_DEPS_CFG=ct_deps.config $(REBAR) compile
	REBAR_EXTRA_DEPS_CFG=ct_deps.config $(REBAR) skip_deps=true ct

rebar_script_test:
	./test_rebar_config_script.sh

test: compile ct

dialyzer: $(DEPS_PLT)
	dialyzer \
		--fullpath \
		--plt $(DEPS_PLT) \
		$(DIALYZER_WARNINGS) \
		-r ./ebin

$(DEPS_PLT):
	@echo Building local plt at $(DEPS_PLT)
	@echo
	dialyzer \
		--build_plt \
		--output_plt $(DEPS_PLT) \
		--apps $(DIALYZER_APPS) \
		-r deps

dialyzer-add-to-plt: $(DEPS_PLT)
	@echo Adding to local plt at $(DEPS_PLT)
	@echo
	dialyzer \
		--add_to_plt \
		--plt $(DEPS_PLT) \
		--output_plt $(DEPS_PLT) \
		--apps $(DIALYZER_APPS) \
		-r deps

shell: deps compile
	@erl $(ERLFLAGS)

typer:
	typer --plt $(DEPS_PLT) -I ./include -r ./src

xref: all
	$(REBAR) xref skip_deps=true

clean-common-test-data:
	- rm -rf $(CURDIR)/{test,extra_test}/*.beam
	- rm -rf $(CURDIR)/logs

#
# This rule assumes that doc/*.md files are all generated.
#
clean-doc-data:
	- rm -f $(CURDIR)/doc/*.html
	- rm -f $(CURDIR)/doc/edoc-info
	- rm -f $(CURDIR)/doc/*.md

clean: clean-common-test-data
	- rm -rf $(CURDIR)/ebin
	$(REBAR) skip_deps=true clean

distclean: clean clean-doc-data
	- rm -rf $(DEPS_PLT)
	- rm -rvf $(CURDIR)/deps

# ex: ts=4 sts=4 sw=4 noet
