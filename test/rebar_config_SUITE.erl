%%%----------------------------------------------------------------
%%% Purpose: Test suite for ../rebar.config.script
%%%-----------------------------------------------------------------
-module(rebar_config_SUITE).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("test_assertions.hrl").

suite() -> [
        {timetrap, {seconds, 30}}
    ].

init_per_suite(Config) ->
    DataDir = ?config(data_dir, Config),
    ct:pal("DataDir: ~p~n", [DataDir]),
    TestRebarConfig = filename:join(DataDir, "test_rebar.config"),
    ct:pal("TestRebarConfig : ~p~n", [TestRebarConfig ]),
    {ok, RebarCfg} = file:consult(TestRebarConfig),
    ct:pal("test_rebar.config:~n~p~n", [RebarCfg]),
    Binding = erl_eval:add_binding('CONFIG', RebarCfg,
                                   erl_eval:new_bindings()),
    [{rebar_cfg, RebarCfg}, {binding, Binding} | Config].

end_per_suite(_Config) ->
    ok.

init_per_group(_GroupName, Config) ->
    Config.

end_per_group(_GroupName, _Config) ->
    ok.

init_per_testcase(_Case, Config) ->
    clean_env(),
    %ct:pal("Current rebar binding:~n~p~n", [value(binding, Config)]),
    Config.

end_per_testcase(_Case, _Config) ->
    clean_env(),
    %ct:pal("Current rebar binding:~n~p~n", [value(binding, _Config)]),
    ok.


groups() ->
    [
     {
      rebar, [],
      [
       syntax_test,
       version_test1,
       version_test2,
       version_test3,
       edown_target_test,
       edown_top_level_url_test,
       combined_test,
       all_undef_test
      ]
     }
    ].

all() ->
    [
        {group, rebar}
    ].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% GROUP:rebar
%%--------------------------------------------------------------------
syntax_test(doc) ->
    ["Ensure syntax of rebar.config.script is correct"];
syntax_test(suite) ->
    [];
syntax_test(Config) ->
    rebind_rebar_config(Config).

version_test1(doc) ->
    ["Ensure edoc version macro is defined correctly when"
     "there is no APP_VERSION file or env var"];
version_test1(suite) ->
    [];
version_test1(Config) ->
    ?assertEqual(rebind_rebar_config(Config), value(rebar_cfg, Config)),
    ok.

version_test2(doc) ->
    [
     "Ensure edoc version macro is defined correctly when",
     "there is no APP_VERSION file but the APP_VERSION env var",
     "is defined"
    ];
version_test2(suite) ->
    [];
version_test2(Config) ->
    ExpectedAppVsn = "1.2.3",
    AppVsn = "\n \n  " ++ ExpectedAppVsn ++ " \n \n\n",
    os:putenv("APP_VERSION", AppVsn),
    Def = edoc_opts_def(rebind_rebar_config(Config)),
    %ct:pal("Rebound edoc_opts.def: ~p~n", [Def]),
    _ = ?assertEqual(value(version, Def), ExpectedAppVsn),
    ok.

version_test3(doc) ->
    ["Ensure edoc version macro is defined correctly using APP_VERSION file"];
version_test3(suite) ->
    [];
version_test3(Config) ->
    VsnFile = "APP_VERSION",
    ExpectedAppVsn = "1.2.3",
    FileVsn = "\n \n  " ++ ExpectedAppVsn ++ " \n \n\n",
    ok = file:write_file(VsnFile, FileVsn),
    _ = ?assertEqual(value(version,
                           edoc_opts_def(rebind_rebar_config(Config))),
                     ExpectedAppVsn),
    ok.

edown_target_test(doc) ->
    ["Ensure that EDOWN_TARGET does the right thing"];
edown_target_test(suite) ->
    [];
edown_target_test(Config) ->
    lists:foldl(fun(Target, _) ->
                        os:putenv("EDOWN_TARGET", Target),
                        NewCfg = rebind_rebar_config(Config),
                        ?assertEqual(Target, edown_target(NewCfg))
                end, [], ["github", "stash"]),
    ok.

edown_top_level_url_test(doc) ->
    ["Ensure that EDOWN_TOP_LEVEL_README_URL does the right thing"];
edown_top_level_url_test(suite) ->
    [];
edown_top_level_url_test(Config) ->
    Url = "Some bogus URL",
    os:putenv("EDOWN_TOP_LEVEL_README_URL", Url),
    NewCfg = rebind_rebar_config(Config),
    %% Check that edoc_opts.edown_target is the same as the env var
    ?assertEqual(Url, edown_url(NewCfg)),
    ok.

combined_test(doc) ->
    ["Ensure that the script does the right thing when all env vars are set"];
combined_test(suite) ->
    [];
combined_test(Config) ->
    os:putenv("EDOWN_TARGET", "github"),
    os:putenv("EDOWN_TOP_LEVEL_README_URL",
              "http://github.com/SilentCircle/sc_push_lib"),

    NewCfg = rebind_rebar_config(Config),

    %% Check that edoc_opts.edown_target is the same as the env var
    ?assertEqual(os:getenv("EDOWN_TARGET"), edown_target(NewCfg)),
    %% Check that edoc_opts.edown_target is the same as the env var
    ?assertEqual(os:getenv("EDOWN_TOP_LEVEL_README_URL"), edown_url(NewCfg)),
    ok.

all_undef_test(doc) ->
    ["Ensure that the script does the right thing when no env vars are set"];
all_undef_test(suite) ->
    [];
all_undef_test(Config) ->
    ?assertEqual(rebind_rebar_config(Config),value(rebar_cfg, Config)),
    ok.

%%====================================================================
%% General helper functions
%%====================================================================
value(Key, Config) when is_list(Config) ->
    V = proplists:get_value(Key, Config),
    ?assertMsg(V =/= undefined, "Required key missing: ~p~n", [Key]),
    V.

edown_target(RebarCfg) ->
    atom_to_list(value(edown_target, value(edoc_opts, RebarCfg))).

edown_url(RebarCfg) ->
    {_Readme, Url} = value(top_level_readme, value(edoc_opts, RebarCfg)),
    Url.

edoc_opts_def(RebarCfg) ->
    proplists:get_value(def, value(edoc_opts, RebarCfg), []).

%% Clean up environment variables
clean_env() ->
    _ = lists:foreach(fun(EnvVar) -> os:unsetenv(EnvVar) end,
                      ["EDOWN_TARGET", "EDOWN_TOP_LEVEL_README_URL",
                       "APP_VERSION"]),
    _ = file:delete("APP_VERSION"),
    ok.

rebind_rebar_config(Config) ->
    %% Run the rebar.config.script on the binding to get the
    %% modified rebar config.
    RebarDir = os:getenv("REBAR_DIR"),
    TestScript = filename:join(RebarDir, "rebar.config.script"),
    {ok, NewCfg} = file:script(TestScript, value(binding, Config)),
    NewCfg.

