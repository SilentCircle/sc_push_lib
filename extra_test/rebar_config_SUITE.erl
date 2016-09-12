%%%----------------------------------------------------------------
%%% Purpose: Test suite for ../rebar.config.script
%%%-----------------------------------------------------------------
-module(rebar_config_SUITE).

-include_lib("common_test/include/ct.hrl").

-export([all/0,
         suite/0,
         groups/0,
         init_per_suite/1,
         end_per_suite/1,
         init_per_group/2,
         end_per_group/2,
         init_per_testcase/2,
         end_per_testcase/2]).

-export([
        syntax_test/1,
        version_test1/1,
        version_test2/1,
        version_test3/1,
        extra_deps_test/1,
        edown_target_test/1,
        edown_top_level_url_test/1,
        combined_test/1,
        all_undef_test/1
    ]).

-include("test_assertions.hrl").

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% Function: suite() -> Info
%%
%% Info = [tuple()]
%%   List of key/value pairs.
%%
%% Description: Returns list of tuples to set default properties
%%              for the suite.
%%
%% Note: The suite/0 function is only meant to be used to return
%% default data values, not perform any other operations.
%%--------------------------------------------------------------------
suite() -> [
        {timetrap, {seconds, 30}}
    ].

%%--------------------------------------------------------------------
%% Function: init_per_suite(Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the suite.
%%
%% Description: Initialization before the suite.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_suite(Config) ->
    TestDir = os:getenv("TEST_DIR"),
    TestRebarConfig = filename:join(TestDir, "test_rebar.config"),
    {ok, RebarCfg} = file:consult(TestRebarConfig),
    ct:pal("test_rebar.config:~n~p~n", [RebarCfg]),
    ct:pal("Current directory: ~p~n", [begin {ok, D} = file:get_cwd(), D end]),
    Binding = erl_eval:add_binding('CONFIG', RebarCfg,
                                   erl_eval:new_bindings()),
    [{rebar_cfg, RebarCfg}, {binding, Binding} | Config].

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% Description: Cleanup after the suite.
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_group(GroupName, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% GroupName = atom()
%%   Name of the test case group that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%% Reason = term()
%%   The reason for skipping all test cases and subgroups in the group.
%%
%% Description: Initialization before each test case group.
%%--------------------------------------------------------------------
init_per_group(_GroupName, Config) ->
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_group(GroupName, Config0) ->
%%               void() | {save_config,Config1}
%%
%% GroupName = atom()
%%   Name of the test case group that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding configuration data for the group.
%%
%% Description: Cleanup after each test case group.
%%--------------------------------------------------------------------
end_per_group(_GroupName, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% Function: init_per_testcase(TestCase, Config0) ->
%%               Config1 | {skip,Reason} | {skip_and_save,Reason,Config1}
%%
%% TestCase = atom()
%%   Name of the test case that is about to run.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for skipping the test case.
%%
%% Description: Initialization before each test case.
%%
%% Note: This function is free to add any key/value pairs to the Config
%% variable, but should NOT alter/remove any existing entries.
%%--------------------------------------------------------------------
init_per_testcase(_Case, Config) ->
    clean_env(),
    %ct:pal("Current rebar binding:~n~p~n", [value(binding, Config)]),
    Config.

%%--------------------------------------------------------------------
%% Function: end_per_testcase(TestCase, Config0) ->
%%               void() | {save_config,Config1} | {fail,Reason}
%%
%% TestCase = atom()
%%   Name of the test case that is finished.
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%% Reason = term()
%%   The reason for failing the test case.
%%
%% Description: Cleanup after each test case.
%%--------------------------------------------------------------------
end_per_testcase(_Case, _Config) ->
    clean_env(),
    %ct:pal("Current rebar binding:~n~p~n", [value(binding, _Config)]),
    ok.


%%--------------------------------------------------------------------
%% Function: groups() -> [Group]
%%
%% Group = {GroupName,Properties,GroupsAndTestCases}
%% GroupName = atom()
%%   The name of the group.
%% Properties = [parallel | sequence | Shuffle | {RepeatType,N}]
%%   Group properties that may be combined.
%% GroupsAndTestCases = [Group | {group,GroupName} | TestCase]
%% TestCase = atom()
%%   The name of a test case.
%% Shuffle = shuffle | {shuffle,Seed}
%%   To get cases executed in random order.
%% Seed = {integer(),integer(),integer()}
%% RepeatType = repeat | repeat_until_all_ok | repeat_until_all_fail |
%%              repeat_until_any_ok | repeat_until_any_fail
%%   To get execution of cases repeated.
%% N = integer() | forever
%%
%% Description: Returns a list of test case group definitions.
%%--------------------------------------------------------------------
groups() ->
    [
     {
      rebar, [],
      [
       syntax_test,
       version_test1,
       version_test2,
       version_test3,
       extra_deps_test,
       edown_target_test,
       edown_top_level_url_test,
       combined_test,
       all_undef_test
      ]
     }
    ].

%%--------------------------------------------------------------------
%% Function: all() -> GroupsAndTestCases | {skip,Reason}
%%
%% GroupsAndTestCases = [{group,GroupName} | TestCase]
%% GroupName = atom()
%%   Name of a test case group.
%% TestCase = atom()
%%   Name of a test case.
%% Reason = term()
%%   The reason for skipping all groups and test cases.
%%
%% Description: Returns the list of groups and test cases that
%%              are to be executed.
%%--------------------------------------------------------------------
all() ->
    [
        {group, rebar}
    ].

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

% t_1(doc) -> ["t/1 should return 0 on an empty list"];
% t_1(suite) -> [];
% t_1(Config) when is_list(Config)  ->
%     ?line 0 = t:foo([]),
%     ok.
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

extra_deps_test(doc) ->
    ["Ensure that REBAR_EXTRA_DEPS_CFG does the right thing"];
extra_deps_test(suite) ->
    [];
extra_deps_test(Config) ->
    %% Specify the file that has the extra deps
    TestDir = os:getenv("TEST_DIR"),
    ExtraDepsFile = filename:join(TestDir, "test_ct_deps.config"),
    os:putenv("REBAR_EXTRA_DEPS_CFG", ExtraDepsFile),

    NewCfg = rebind_rebar_config(Config),

    %% Get the extra deps
    {ok, ExtraDepsCfg} = file:consult(os:getenv("REBAR_EXTRA_DEPS_CFG")),
    ExtraDeps = value(deps, ExtraDepsCfg),
    NewDeps = value(deps, NewCfg),
    %% Check that deps from the extra deps made it into the new config
    _ = [?assert(lists:member(Dep, NewDeps)) || Dep <- ExtraDeps],
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
    %% Specify the file that has the extra deps
    TestDir = os:getenv("TEST_DIR"),
    ExtraDepsFile = filename:join(TestDir, "test_ct_deps.config"),
    os:putenv("REBAR_EXTRA_DEPS_CFG", ExtraDepsFile),
    os:putenv("EDOWN_TARGET", "github"),
    os:putenv("EDOWN_TOP_LEVEL_README_URL",
              "https://code.silentcircle.org/projects/SCPS/repos/sc_push_lib"),

    NewCfg = rebind_rebar_config(Config),

    %% Get the extra deps
    {ok, ExtraDepsCfg} = file:consult(os:getenv("REBAR_EXTRA_DEPS_CFG")),
    ExtraDeps = value(deps, ExtraDepsCfg),
    NewDeps = value(deps, NewCfg),
    %% Check that deps from the extra deps made it into the new config
    _ = [?assert(lists:member(Dep, NewDeps)) || Dep <- ExtraDeps],
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
                      ["REBAR_EXTRA_DEPS_CFG",
                       "EDOWN_TARGET",
                       "EDOWN_TOP_LEVEL_README_URL",
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

