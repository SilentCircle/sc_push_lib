%%%----------------------------------------------------------------
%%% Purpose: Test suite for the 'sc_push_lib' application.
%%%-----------------------------------------------------------------

-module(sc_push_lib_SUITE).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("test_assertions.hrl").

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
suite() -> [
        {timetrap, {seconds, 30}}
    ].

%%--------------------------------------------------------------------
init_per_suite(Config) ->
    Config.

%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    ok.

%%--------------------------------------------------------------------
init_per_group(_Group, Config) ->
    Config.

%%--------------------------------------------------------------------
end_per_group(_GroupName, _Config) ->
    ok.

%%--------------------------------------------------------------------
init_per_testcase(_Case, Config) ->
    ok = application:ensure_started(sasl),
    _ = application:load(lager),
    [ok = application:set_env(lager, K, V) || {K, V} <- lager_config(Config)],
    db_create(Config),
    {ok, Apps} = application:ensure_all_started(sc_push_lib),
    Started = {apps, [sasl | Apps]},
    [Started | proplists:delete(apps, Config)].

%%--------------------------------------------------------------------
end_per_testcase(_Case, Config) ->
    Apps = lists:reverse(value(apps, Config)),
    ct:pal("Config:~n~p~n", [Config]),
    _ = [ok = application:stop(App) || App <- Apps],
    code:purge(lager_console_backend), % ct gives error otherwise
    db_destroy(Config),
    Config.

%%--------------------------------------------------------------------
groups() ->
    [
     {sc_push_lib, [], [sc_push_lib_test]},
     {reqmgr, [], [reqmgr_test]},
     {sc_config, [], sc_config_test_cases()}
    ].

sc_config_test_cases() ->
    [
     sc_config_test,
     sc_config_select_test,
     sc_config_delete_test,
     sc_config_get_all_keys_test,
     sc_config_get_all_values_test,
     sc_config_delete_all_test
    ].

%%--------------------------------------------------------------------
all() ->
    [
        {group, sc_push_lib},
        {group, reqmgr},
        {group, sc_config}
    ].

%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% TEST CASES
%%--------------------------------------------------------------------

% t_1(doc) -> ["t/1 should return 0 on an empty list"];
% t_1(suite) -> [];
% t_1(Config) when is_list(Config)  ->
%     ?line 0 = t:foo([]),
%     ok.
%%--------------------------------------------------------------------
%% Group: sc_push_lib
%%--------------------------------------------------------------------
sc_push_lib_test(doc) ->
    ["Test sc_push_lib:register_service, unregister_service, get_service_config"];
sc_push_lib_test(suite) ->
    [];
sc_push_lib_test(_Config) ->
    SvcName = some_test_service,
    SvcConfig = [{name, SvcName}],
    % Register
    ok = sc_push_lib:register_service(SvcConfig),
    % Get service config (happy)
    {ok, SvcConfig} = sc_push_lib:get_service_config(SvcName),
    % Get service config (unhappy)
    {error, {unregistered_service,
             foobarbaz}} = sc_push_lib:get_service_config(foobarbaz),
    % Unregister nonexistent service
    ok = sc_push_lib:unregister_service(foobarbaz),
    % Unregister service we just registered
    ok = sc_push_lib:unregister_service(SvcName),
    % Check it's gone
    {error, {unregistered_service,
             SvcName}} = sc_push_lib:get_service_config(SvcName).

%%--------------------------------------------------------------------
%% Group: reqmgr
%%--------------------------------------------------------------------
reqmgr_test(doc) ->
    ["Test sc_push_req_mgr:add,delete,lookup"];
reqmgr_test(suite) ->
    [];
reqmgr_test(Config) ->
    ID = make_ref(),
    Req = <<"$$test_req$$">>,

    undefined = sc_push_req_mgr:lookup(make_ref()),
    ok = sc_push_req_mgr:add(ID, Req),

    % Check props
    PL = sc_push_req_mgr:lookup(ID),
    ?assert(PL /= undefined),
    ID = value(id, PL),
    Req = value(req, PL),
    % Timestamp is posix time in seconds
    ?assert(is_integer(value(ts, PL))),

    Callback = value(callback, PL),
    {module, sc_push_req_mgr} = erlang:fun_info(Callback, module),
    {name, default_callback} = erlang:fun_info(Callback, name),
    {arity, 1} = erlang:fun_info(Callback, arity),

    ok = (Callback)(PL),

    PL = sc_push_req_mgr:remove(ID),
    undefined = sc_push_req_mgr:remove(ID),

    % Kick off a sweep
    ok = sc_push_req_mgr:sweep(),

    % Kick off a sync sweep
    {ok, _} = sc_push_req_mgr:sync_sweep(),

    % Add a req and kick off an async sweep that will remove all requests
    ok = sc_push_req_mgr:add(ID, Req),
    ok = sc_push_req_mgr:sweep(0),

    % Add a req and kick off a sync sweep that will remove all requests
    sc_push_req_mgr:remove_all(),
    ok = sc_push_req_mgr:add(ID, Req),
    L = sc_push_req_mgr:all_req(),
    ?assert(length(L) > 0),
    {ok, NumDel} = sc_push_req_mgr:sync_sweep(0),
    ?assertEqual(NumDel, 1),
    undefined = sc_push_req_mgr:remove(ID),

    % Test bad gen_server requests
    try_bad_gen_server_req(sc_push_req_mgr),

    Config.

%%--------------------------------------------------------------------
%% Group: sc_config
%%--------------------------------------------------------------------
sc_config_test(doc) ->
    ["Test sc_config:set,get,delete"];
sc_config_test(suite) ->
    [];
sc_config_test(Config) ->
    Key = make_ref(),
    Val = <<"$$test_val$$">>,
    undefined = sc_config:get(make_ref()),
    ok = sc_config:set(Key, Val),
    Val = sc_config:get(Key),
    Val = sc_config:get(Key, my_default),
    ok = sc_config:delete(Key),
    undefined = sc_config:get(Key),
    my_default = sc_config:get(Key, my_default),
    try_bad_gen_server_req(sc_config),
    Config.

%%--------------------------------------------------------------------
sc_config_select_test(doc) ->
    ["test sc_config:select"];
sc_config_select_test(suite) ->
    [];
sc_config_select_test(Config) ->
    Foo = [{{foo, V}, {fooval, V}} || V <- lists:seq(1, 50)],
    Bar = [{{bar, V}, {barval, V}} || V <- lists:seq(51, 100)],
    BarVals = lists:sort([V || {_, V} <- Bar]),
    _ = [ok = sc_config:set(K, V) || {K, V} <- Foo ++ Bar],
    BarVals = lists:sort(sc_config:select({bar, '_'})),
    Config.

%%--------------------------------------------------------------------
sc_config_delete_test(doc) ->
    ["test sc_config:delete_keys"];
sc_config_delete_test(suite) ->
    [];
sc_config_delete_test(Config) ->
    Foo = [{{foo, V}, {fooval, V}} || V <- lists:seq(1, 50)],
    Bar = [{{bar, V}, {barval, V}} || V <- lists:seq(51, 100)],
    BarVals = lists:sort([V || {_, V} <- Bar]),
    _ = [ok = sc_config:set(K, V) || {K, V} <- Foo ++ Bar],
    BarVals = lists:sort(sc_config:select({bar, '_'})),
    ok = sc_config:delete_keys({bar, '_'}),
    [] = sc_config:select({bar, '_'}),
    Config.

%%--------------------------------------------------------------------
sc_config_get_all_keys_test(doc) ->
    ["test sc_config:get_all_keys"];
sc_config_get_all_keys_test(suite) ->
    [];
sc_config_get_all_keys_test(Config) ->
    Foo = [{{foo, V}, {fooval, V}} || V <- lists:seq(1, 50)],
    Bar = [{{bar, V}, {barval, V}} || V <- lists:seq(51, 100)],
    _ = [ok = sc_config:set(K, V) || {K, V} <- Foo ++ Bar],
    AllKeys = lists:sort([K || {K, _} <- Foo ++ Bar]),
    AllKeys = lists:sort(sc_config:get_all_keys()),
    Config.

%%--------------------------------------------------------------------
sc_config_get_all_values_test(doc) ->
    ["test sc_config:get_all_values"];
sc_config_get_all_values_test(suite) ->
    [];
sc_config_get_all_values_test(Config) ->
    Foo = [{{foo, V}, {fooval, V}} || V <- lists:seq(1, 50)],
    Bar = [{{bar, V}, {barval, V}} || V <- lists:seq(51, 100)],
    _ = [ok = sc_config:set(K, V) || {K, V} <- Foo ++ Bar],
    AllValues = lists:sort([V || {_, V} <- Foo ++ Bar]),
    AllValues = lists:sort(sc_config:get_all_values()),
    Config.

%%--------------------------------------------------------------------
sc_config_delete_all_test(doc) ->
    ["test sc_config:delete_all"];
sc_config_delete_all_test(suite) ->
    [];
sc_config_delete_all_test(Config) ->
    Foo = [{{foo, V}, {fooval, V}} || V <- lists:seq(1, 50)],
    _ = [ok = sc_config:set(K, V) || {K, V} <- Foo],
    ok = sc_config:delete_all(),
    [] = sc_config:get_all_keys(),
    Config.

%%====================================================================
%% Internal helper functions
%%====================================================================
try_bad_gen_server_req(SvrRef) ->
    % Try a bad request
    {error, bad_request} = gen_server:call(SvrRef, {foobar, baz}),

    % Try unknown cast and info calls
    ok = gen_server:cast(SvrRef, {foobar, baz}),
    {foobar, baz} = SvrRef ! {foobar, baz}.

%%====================================================================
%% Lager support
%%====================================================================
lager_config(Config) ->
    PrivDir = value(priv_dir, Config), % Standard CT variable
    ErrorLog = filename:join(PrivDir, "error.log"),
    ConsoleLog = filename:join(PrivDir, "console.log"),
    CrashLog = filename:join(PrivDir, "crash.log"),

    [
        %% What handlers to install with what arguments
        {handlers, [
                {lager_console_backend, info},
                {lager_file_backend, [
                        {file, ErrorLog},
                        {level, error},
                        {size, 10485760},
                        {date, "$D0"},
                        {count, 5}
                    ]
                },
                {lager_file_backend, [
                        {file, ConsoleLog},
                        {level, info},
                        {size, 10485760},
                        {date, "$D0"},
                        {count, 5}
                    ]
                }
            ]
        },
        %% Whether to write a crash log, and where. Undefined means no crash logger.
        {crash_log, CrashLog}
    ].

%%====================================================================
%% General helper functions
%%====================================================================
value(Key, Config) when is_list(Config) ->
    V = proplists:get_value(Key, Config),
    ?assertMsg(V =/= undefined, "Required key missing: ~p~n", [Key]),
    V.

%%--------------------------------------------------------------------
db_create(Config) ->
    PrivDir = value(priv_dir, Config), % Standard CT variable
    MnesiaDir = filename:join(PrivDir, "mnesia"),
    ok = application:set_env(mnesia, dir, MnesiaDir),
    mnesia:stop(),
    mnesia:delete_schema([node()]),
    ok = mnesia:create_schema([node()]).

%%--------------------------------------------------------------------
db_destroy(Config) ->
    ok = mnesia:delete_schema([node()]).
