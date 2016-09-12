%%====================================================================
%% Common Test Test Spec
%%====================================================================

{include, ["include"]}.
{cover, "./sc_push_lib.cover.spec"}.
{config, ["test/test.config"]}.
{suites, "./_build/test/lib/sc_push_lib", [rebar_config_SUITE, sc_push_lib_SUITE]}.
