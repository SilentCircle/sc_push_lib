%%====================================================================
%% Common Test Test Spec
%%====================================================================

{include, ["include"]}.
{config, ["test/test.config"]}.
{suites, "test", [rebar_config_SUITE,
                  sc_push_lib_SUITE,
                  sc_push_lib_db_SUITE]}.
