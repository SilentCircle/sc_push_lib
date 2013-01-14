%%%----------------------------------------------------------------
%%% Purpose: Test suite for the 'sc_push_lib' application.
%%%-----------------------------------------------------------------

-module(sc_push_lib_SUITE).

-include_lib("common_test/include/ct.hrl").

-compile(export_all).

-define(assertMsg(Cond, Fmt, Args),
    case (Cond) of
        true ->
            ok;
        false ->
            ct:fail("Assertion failed: ~p~n" ++ Fmt, [??Cond] ++ Args)
    end
).

-define(assert(Cond), ?assertMsg((Cond), "", [])).
-define(
    assertEqual(LHS, RHS),
        ?assertMsg(
            LHS == RHS,
            "~s=~p, ~s=~p", [??LHS, LHS, ??RHS, RHS]
        )
).
-define(assertThrow(Expr, Class, Reason),
    begin
            ok = (fun() ->
                    try (Expr) of
                        Res ->
                            {unexpected_return, Res}
                    catch
                        C:R ->
                            case {C, R} of
                                {Class, Reason} ->
                                    ok;
                                _ ->
                                    {unexpected_exception, {C, R}}
                            end
                    end
            end)()
    end
).

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
        {timetrap, {seconds, 30}},
        {require, registration}
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
    ok = application:start(sasl),
    ok = application:load(lager),
    [ok = application:set_env(lager, K, V) || {K, V} <- lager_config(Config)],
    ok = application:start(lager),
    Registration = ct:get_config(registration),
    ct:pal("Registration: ~p~n", [Registration]),
    [{registration, Registration} | Config].

%%--------------------------------------------------------------------
%% Function: end_per_suite(Config0) -> void() | {save_config,Config1}
%%
%% Config0 = Config1 = [tuple()]
%%   A list of key/value pairs, holding the test case configuration.
%%
%% Description: Cleanup after the suite.
%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    ok = application:stop(lager),
    ok = application:unload(lager),
    code:purge(lager_console_backend), % ct gives error otherwise
    ok = application:stop(sasl),
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
    init_per_testcase_common(Config).

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
end_per_testcase(_Case, Config) ->
    end_per_testcase_common(Config).

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
            registration,
            [],
            [
                make_id_test,
                make_push_props_test,
                register_id_test,
                reregister_id_test,
                register_ids_test,
                register_ids_bad_id_test,
                deregister_ids_bad_id_test,
                get_registration_info_test,
                get_registration_info_not_found_test
            ]
        },
        {
            reqmgr,
            [],
            [
                reqmgr_test
            ]
        },
        {
            sc_config,
            [],
            [
                sc_config_test
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
        {group, registration},
        {group, reqmgr},
        {group, sc_config}
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
%% GROUP:registration
%%--------------------------------------------------------------------
make_id_test(doc) ->
    ["sc_push_reg_api:make_id/1 should create a canonical registration ID"];
make_id_test(suite) ->
    [];
make_id_test(_Config) ->
    ExpSvc = 'apns',
    ExpToken = <<"abcdef">>,
    ExpectedID = {ExpSvc, ExpToken},
    ExpectedID = sc_push_reg_api:make_id(ExpSvc, ExpToken),
    ExpectedID = sc_push_reg_api:make_id(atom_to_list(ExpSvc), ExpToken),
    ExpectedID = sc_push_reg_api:make_id(atom_to_list(ExpSvc), binary_to_list(ExpToken)),
    ok.

make_push_props_test(doc) ->
    ["Test sc_push_reg_api:make_sc_push_props/5"];
make_push_props_test(suite) ->
    [];
make_push_props_test(Config) ->
    Props = sc_push_reg_api:make_sc_push_props(p1, p2, p3, p4, p5),
    p1 = value(service, Props),
    p2 = value(token, Props),
    p3 = value(tag, Props),
    p4 = value(app_id, Props),
    p5 = value(dist, Props),
    Config.

register_id_test(doc) ->
    ["sc_push_reg_api:register_id/1 should register a 'device'"];
register_id_test(suite) ->
    [];
register_id_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL),
    ct:pal("Registered ~p~n", [RegPL]),
    deregister_id(RegPL).

reregister_id_test(doc) ->
    ["sc_push_reg_api:reregister_id/2 should reregister an existing reg with a new ID"];
reregister_id_test(suite) ->
    [];
reregister_id_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL),
    ct:pal("Registered ~p~n", [RegPL]),

    OldService = value(service, RegPL),
    OldTok = value(token, RegPL),
    OldId = sc_push_reg_api:make_id(OldService, OldTok),
    NewTok = <<"thisisanewtoken">>,
    ok = sc_push_reg_api:reregister_id(OldId, NewTok),

    Tag = value(tag, RegPL),
    ListOfRegPL = sc_push_reg_api:get_registration_info(Tag),
    [[{_,_}|_] = NewRegPL] = ListOfRegPL,

    % Does this have the tag?
    NewTag = value(tag, NewRegPL),
    % Does this have the *right* tag?
    NewTag = sc_util:to_bin(Tag),
    % Does this have the right service and token?
    OldService = value(service, NewRegPL),
    NewTok = value(token, NewRegPL),

    deregister_id(RegPL),
    deregister_id(NewRegPL).

register_ids_test(doc) ->
    ["sc_push_reg_api:register_ids/1 should register a 'device'"];
register_ids_test(suite) ->
    [];
register_ids_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_ids([RegPL]),
    ct:pal("Registered ~p~n", [RegPL]),
    deregister_ids(RegPL),
    ok.

register_ids_bad_id_test(doc) ->
    ["sc_push_reg_api:register_ids/1 should fail due to bad input"];
register_ids_bad_id_test(suite) ->
    [];
register_ids_bad_id_test(_Config) ->
    ?assertThrow(sc_push_reg_api:register_ids(totally_invalid_input), error, function_clause),
    ?assertThrow(sc_push_reg_api:register_ids([totally_invalid_input]), error, function_clause),
    ?assertThrow(sc_push_reg_api:register_ids([{totally_invalid_input, foo}]), error, function_clause),
    {error, _} = sc_push_reg_api:register_ids([[{unknown_key, foo}]]),

    ct:pal("register_ids correctly identified bad input~n", []),
    ok.

deregister_ids_bad_id_test(doc) ->
    ["sc_push_reg_api:deregister_ids/1 should fail due to bad input"];
deregister_ids_bad_id_test(suite) ->
    [];
deregister_ids_bad_id_test(Config) ->
    ?assertThrow(sc_push_reg_api:deregister_ids(totally_invalid_input), error, function_clause),
    {error, {bad_reg_id, _}} = sc_push_reg_api:deregister_ids([totally_invalid_input]),
    {error, _} = sc_push_reg_api:deregister_ids([{<<1,2,3>>, <<4,5,6>>}]),

    ct:pal("deregister_ids correctly identified bad input~n", []),
    Config.

get_registration_info_test(doc) ->
    ["sc_push_reg_api:get_registration_info/1 should get the correct reg info for a tag"];
get_registration_info_test(suite) ->
    [];
get_registration_info_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL),
    Tag = value(tag, RegPL),
    ListOfRegPL = sc_push_reg_api:get_registration_info(Tag),
    % Does this look like a list of one non-empty proplist?
    [[{_,_}|_] = NewRegPL] = ListOfRegPL,
    % Does this have the tag?
    NewTag = value(tag, NewRegPL),
    % Does this have the *right* tag?
    % Note that the reginfo always comes back as binary data
    % except for 'service', which is an atom.
    NewTag = sc_util:to_bin(Tag),
    ct:pal("Got reginfo for tag ~p:~n~p", [NewTag, NewRegPL]),
    deregister_id(RegPL).

get_registration_info_not_found_test(doc) ->
    ["sc_push_reg_api:get_registration_info/1 should not find this reg info"];
get_registration_info_not_found_test(suite) ->
    [];
get_registration_info_not_found_test(Config) ->
    FakeTag = <<"$$Completely bogus tag$$">>,
    notfound = sc_push_reg_api:get_registration_info(FakeTag),
    ct:pal("Got expected 'notfound' result for tag ~p~n", [FakeTag]),
    ok.

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

%%====================================================================
%% Internal helper functions
%%====================================================================
init_per_testcase_common(Config) ->
    (catch end_per_testcase_common(Config)),
    ok = mnesia:create_schema([node()]),
    ok = mnesia:start(),
    ok = application:start(jsx),
    ok = application:start(sc_util),
    ok = application:start(sc_push_lib),
    Config.

end_per_testcase_common(Config) ->
    ok = application:stop(sc_push_lib),
    ok = application:stop(sc_util),
    ok = application:stop(jsx),
    stopped = mnesia:stop(),
    ok = mnesia:delete_schema([node()]),
    Config.

deregister_id(RegPL) ->
    Service = value(service, RegPL),
    Token = value(token, RegPL),
    ID = sc_push_reg_api:make_id(Service, Token),
    ok = sc_push_reg_api:deregister_id(ID),
    ct:pal("Deregistered ID ~p~n", [ID]).

deregister_ids(RegPL) ->
    Service = value(service, RegPL),
    Token = value(token, RegPL),
    ID = sc_push_reg_api:make_id(Service, Token),
    ok = sc_push_reg_api:deregister_ids([ID]),
    ct:pal("Deregistered IDs ~p~n", [ID]).

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
    [
        %% What handlers to install with what arguments
        {handlers, [
                {lager_console_backend, info},
                {lager_file_backend, [
                        {filename:join(PrivDir, "error.log"), error, 10485760, "$D0", 5},
                        {filename:join(PrivDir, "console.log"), info, 10485760, "$D0", 5}
                    ]
                }
            ]},
        %% Whether to write a crash log, and where. Undefined means no crash logger.
        {crash_log, filename:join(PrivDir, "crash.log")}
    ].

%%====================================================================
%% General helper functions
%%====================================================================
value(Key, Config) when is_list(Config) ->
    V = proplists:get_value(Key, Config),
    ?assertMsg(V =/= undefined, "Required key missing: ~p~n", [Key]),
    V.

