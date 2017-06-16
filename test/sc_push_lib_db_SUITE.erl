%%%----------------------------------------------------------------
%%% Purpose: Test suite for the registration part of
%%% the 'sc_push_lib' application.
%%%-----------------------------------------------------------------

-module(sc_push_lib_db_SUITE).
-compile(export_all).

-include_lib("common_test/include/ct.hrl").
-include("test_assertions.hrl").

%%--------------------------------------------------------------------
%% COMMON TEST CALLBACK FUNCTIONS
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
suite() -> [
        {timetrap, {seconds, 30}},
        {require, registration},
        {require, databases},
        {require, connect_info},
        {require, lager}
    ].

%%--------------------------------------------------------------------
init_per_suite(Config) ->
    Registration = ct:get_config(registration),
    ct:pal("Registration: ~p~n", [Registration]),
    Databases = ct:get_config(databases),
    ct:pal("Databases: ~p~n", [Databases]),
    ConnectInfo = ct:get_config(connect_info),
    ct:pal("connect_info config: ~p~n", [ConnectInfo]),
    RawLagerConfig = ct:get_config(lager),
    ct:pal("Raw lager config: ~p~n", [RawLagerConfig]),
    LagerConfig = sc_push_lib_test_helper:lager_config(Config,
                                                       RawLagerConfig),
    ct:pal("lager config: ~p~n", [LagerConfig]),
    [{registration, Registration},
     {databases, Databases},
     {connect_info, ConnectInfo},
     {lager, LagerConfig} | Config].

%%--------------------------------------------------------------------
end_per_suite(_Config) ->
    ok.

%%--------------------------------------------------------------------
init_per_group(Group, Config) when Group =:= internal_db;
                                   Group =:= external_db ->
    DBMap = value(databases, Config),
    DBInfo = maps:get(Group, DBMap),
    lists:keystore(dbinfo, 1, Config, {dbinfo, DBInfo});
init_per_group(_Group, Config) ->
    Config.

%%--------------------------------------------------------------------
end_per_group(_GroupName, _Config) ->
    ok.

%%--------------------------------------------------------------------
init_per_testcase(_Case, Config) ->
    DBInfo = value(dbinfo, Config),
    LagerConfig = value(lager, Config),

    ok = application:ensure_started(sasl),
    _ = application:load(lager),
    [ok = application:set_env(lager, K, V) || {K, V} <- LagerConfig],
    ok = application:set_env(sc_push_lib, db_pools, db_pools(DBInfo, Config)),
    {ok, DbPools} = application:get_env(sc_push_lib, db_pools),
    ct:pal("init_per_testcase: DbPools: ~p", [DbPools]),
    db_create(Config),
    {ok, Apps} = application:ensure_all_started(sc_push_lib),
    Started = {apps, [sasl | Apps]},
    [Started | proplists:delete(apps, Config)].

%%--------------------------------------------------------------------
end_per_testcase(_Case, Config) ->
    Apps = lists:reverse(value(apps, Config)),
    ct:pal("Config:~n~p~n", [Config]),
    lists:foreach(fun(App) ->
                          ok = application:stop(App)
                  end, Apps),
    code:purge(lager_console_backend), % ct gives error otherwise
    db_destroy(Config),
    Config.

%%--------------------------------------------------------------------
groups() ->
    [
     {registration, [],
      [{internal_db, [], registration_test_cases()},
       {external_db, [], registration_test_cases()}
      ]}
    ].

registration_test_cases() ->
    [
     make_id_test,
     make_svc_tok_test,
     make_push_props_test,
     is_valid_push_reg_test,
     register_id_test,
     reregister_id_test,
     register_ids_test,
     register_ids_bad_id_test,
     deregister_ids_bad_id_test,
     get_registration_info_test,
     all_registration_info_test,
     get_registration_info_by_id_test,
     get_registration_info_by_device_id_test,
     get_registration_info_by_tag_test,
     get_registration_info_by_svc_tok_test,
     get_registration_info_by_id_not_found_test,
     get_registration_info_not_found_test,
     update_last_invalid_test
    ].

%%--------------------------------------------------------------------
all() ->
    [
        {group, registration, default, [{internal_db, []},
                                        {external_db, []}]}
    ].

%%--------------------------------------------------------------------
%% GROUP INFORMATION FUNCTIONS
%%--------------------------------------------------------------------
group(registration) -> [];
group(internal_db) ->
    [
     {userdata, [{internal_db, mnesia},
                 {external_db, mnesia}]}
    ];
group(external_db) ->
    [
     {userdata, [{internal_db, mnesia},
                 {external_db, postgres}]}
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
%% GROUP:registration
%%--------------------------------------------------------------------
make_id_test(doc) ->
    ["sc_push_reg_api:make_id/2 should create a canonical registration ID"];
make_id_test(suite) ->
    [];
make_id_test(_Config) ->
    {DeviceID, Tag} = ExpectedID = {<<"abcdef">>, <<"12345678">>},
    ExpectedID = sc_push_reg_api:make_id(DeviceID, Tag),
    ExpectedID = {DeviceID, Tag},
    ok.

%%--------------------------------------------------------------------
make_svc_tok_test(doc) ->
    ["sc_push_reg_api:make_svc_tok/2 should create a canonical registration svc_tok"];
make_svc_tok_test(suite) ->
    [];
make_svc_tok_test(_Config) ->
    ExpSvc = 'apns',
    ExpToken = <<"abcdef">>,
    ExpectedID = {ExpSvc, ExpToken},
    ExpectedID = sc_push_reg_api:make_svc_tok(ExpSvc, ExpToken),
    ExpectedID = sc_push_reg_api:make_svc_tok(atom_to_list(ExpSvc), ExpToken),
    ExpectedID = sc_push_reg_api:make_svc_tok(atom_to_list(ExpSvc), binary_to_list(ExpToken)),
    ok.

%%--------------------------------------------------------------------
is_valid_push_reg_test(doc) ->
    ["sc_push_reg_api:is_valid_push_reg/1 should validate proplist"];
is_valid_push_reg_test(suite) ->
    [];
is_valid_push_reg_test(Config) ->
    Service = my_service,
    Token = <<"my_token">>,
    Tag = <<"my_tag">>,
    AppId = <<"my_app_id">>,
    Dist = <<"prod">>,
    DeviceId = <<"test_device_id">>,

    GoodProps = sc_push_reg_db:make_sc_push_props(Service, Token, DeviceId,
                                                  Tag, AppId, Dist,
                                                  erlang:timestamp()),

    true = sc_push_reg_api:is_valid_push_reg(GoodProps),

    BadProps = [{service, 100}],
    false = sc_push_reg_api:is_valid_push_reg(BadProps),

    Config.

%%--------------------------------------------------------------------
make_push_props_test(doc) ->
    ["Test sc_push_reg_db:make_sc_push_props/8"];
make_push_props_test(suite) ->
    [];
make_push_props_test(Config) ->
    Service = my_service,
    Token = <<"my_token">>,
    Tag = <<"my_tag">>,
    AppId = <<"my_app_id">>,
    Dist = <<"prod">>,
    DeviceId = <<"test_device_id">>,
    Modified = erlang:timestamp(),

    Props = sc_push_reg_db:make_sc_push_props(Service, Token, DeviceId, Tag,
                                              AppId, Dist, Modified),
    Service = value(service, Props),
    Token = value(token, Props),
    Tag = value(tag, Props),
    AppId = value(app_id, Props),
    Dist = value(dist, Props),
    DeviceId = value(device_id, Props),
    Modified = value(modified, Props),
    LastInvalidOn = proplists:get_value(last_invalid_on, Props, undefined),

    %% Check that it will work from strings, too (except modified)
    Props1 = sc_push_reg_db:make_sc_push_props(atom_to_list(Service),
                                               binary_to_list(Token),
                                               binary_to_list(DeviceId),
                                               binary_to_list(Tag),
                                               binary_to_list(AppId),
                                               binary_to_list(Dist),
                                               Modified, LastInvalidOn
                                           ),
    Service = value(service, Props1),
    Token = value(token, Props1),
    Tag = value(tag, Props1),
    AppId = value(app_id, Props1),
    Dist = value(dist, Props1),
    DeviceId = value(device_id, Props1),
    Modified = value(modified, Props1),
    LastInvalidOn = proplists:get_value(last_invalid_on, Props1, undefined),

    Config.

%%--------------------------------------------------------------------
register_id_test(doc) ->
    ["sc_push_reg_api:register_id/1 should register a 'device'"];
register_id_test(suite) ->
    [];
register_id_test(Config) ->
    RegPL = value(registration, Config),
    Result = sc_push_reg_api:register_id(RegPL),
    ct:pal("register_id returned ~p~n", [Result]),
    ok = Result,
    ct:pal("Registered ~p~n", [RegPL]),
    deregister_id(RegPL).

%%--------------------------------------------------------------------
reregister_id_test(doc) ->
    ["sc_push_reg_api:reregister_id/2 should reregister an existing reg with a new token"];
reregister_id_test(suite) ->
    [];
reregister_id_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL),
    ct:pal("Registered ~p~n", [RegPL]),

    ID = value(device_id, RegPL),
    Tag = value(tag, RegPL),

    OldID = sc_push_reg_api:make_id(ID, Tag),
    NewTok = <<"thisisanewtoken">>,
    ok = sc_push_reg_api:reregister_id(OldID, NewTok),

    ListOfRegPL = sc_push_reg_api:get_registration_info_by_id(OldID),
    [[{_,_}|_] = NewRegPL] = ListOfRegPL,

    % Does this have the ID?
    NewID = sc_push_reg_api:make_id(value(device_id, NewRegPL),
                                    value(tag, NewRegPL)),
    % Does this have the *right* ID?
    NewID = OldID,
    % Does this have the right service and token?
    OldService = value(service, RegPL),
    OldService = value(service, NewRegPL),

    NewTok = value(token, NewRegPL),

    deregister_id(RegPL),
    deregister_id(NewRegPL).

%%--------------------------------------------------------------------
register_ids_test(doc) ->
    ["sc_push_reg_api:register_ids/1 should register a 'device'"];
register_ids_test(suite) ->
    [];
register_ids_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_ids([RegPL]),
    ct:pal("Registered ~p~n", [RegPL]),
    deregister_ids([RegPL]),
    ok.

%%--------------------------------------------------------------------
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

%%--------------------------------------------------------------------
deregister_ids_bad_id_test(doc) ->
    ["sc_push_reg_api:deregister_ids/1 should fail due to bad input"];
deregister_ids_bad_id_test(suite) ->
    [];
deregister_ids_bad_id_test(Config) ->
    ?assertThrow(sc_push_reg_api:deregister_ids(totally_invalid_input), error, function_clause),
    ?assertThrow(sc_push_reg_api:deregister_ids([totally_invalid_input]), error, function_clause),

    ct:pal("deregister_ids correctly identified bad input~n", []),
    Config.

%%--------------------------------------------------------------------
all_registration_info_test(doc) ->
    ["sc_push_reg_api:all_registration_info/1 should get all reg info"];
all_registration_info_test(suite) ->
    [];
all_registration_info_test(Config) ->
    RegPLs = make_n_reg_ids(20),
    ok = sc_push_reg_api:register_ids(RegPLs),
    NewRegPLs = sc_push_reg_api:all_registration_info(),
    true = reg_pls_equal(RegPLs, NewRegPLs),
    deregister_ids(RegPLs),
    Config.

%%--------------------------------------------------------------------
get_registration_info_test(doc) ->
    ["sc_push_reg_api:get_registration_info/1 should get the correct reg info for a tag"];
get_registration_info_test(suite) ->
    [];
get_registration_info_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL),
    Tag = value(tag, RegPL),
    ListOfRegPL = sc_push_reg_api:get_registration_info(Tag),
    true = is_list(ListOfRegPL),
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

%%--------------------------------------------------------------------
get_registration_info_by_tag_test(doc) ->
    ["sc_push_reg_api:get_registration_info_by_tag/1 should get the correct reg info for a reg tag"];
get_registration_info_by_tag_test(suite) ->
    [];
get_registration_info_by_tag_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL),
    Tag = value(tag, RegPL),
    [NewRegPL] = sc_push_reg_api:get_registration_info_by_tag(Tag),
    % Does this have tag?
    NewTag = value(tag, NewRegPL),
    % Does this have the *right* tag?
    % Note that the reginfo always comes back as binary data
    % except for 'service', which is an atom.
    Tag = value(tag, RegPL),
    NewTag = sc_util:to_bin(Tag),

    ct:pal("Got reginfo for ID ~p:~n~p", [NewTag, NewRegPL]),
    deregister_id(RegPL).

%%--------------------------------------------------------------------
get_registration_info_by_svc_tok_test(doc) ->
    ["sc_push_reg_api:get_registration_info_by_svc_tok/1 should get the correct reg info for service+token"];
get_registration_info_by_svc_tok_test(suite) ->
    [];
get_registration_info_by_svc_tok_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL),
    Svc = value(service, RegPL),
    Tok = value(token, RegPL),

    [NewRegPL] = sc_push_reg_api:get_registration_info_by_svc_tok(Svc, Tok),

    NewSvc = value(service, NewRegPL),
    NewTok = value(token, NewRegPL),

    {NewSvc, NewTok} = {Svc, Tok},

    ct:pal("Got reginfo for svc/tok ~p/~p:~n~p", [NewSvc, NewTok, NewRegPL]),
    deregister_id(RegPL).

%%--------------------------------------------------------------------
get_registration_info_by_id_test(doc) ->
    ["sc_push_reg_api:get_registration_info_by_id/1 should get the correct reg info for a single device ID"];
get_registration_info_by_id_test(suite) ->
    [];
get_registration_info_by_id_test(Config) ->
    RegPL = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL),
    ID = sc_push_reg_api:make_id(value(device_id, RegPL),
                                 value(tag, RegPL)),
    [NewRegPL] = sc_push_reg_api:get_registration_info_by_id(ID),
    % Does this have ID values?
    NewID = sc_push_reg_api:make_id(value(device_id, NewRegPL),
                                    value(tag, NewRegPL)),
    % Does this have the *right* id?
    NewID = ID,

    ct:pal("Got reginfo for ID ~p:~n~p", [NewID, NewRegPL]),
    deregister_id(RegPL).

%%--------------------------------------------------------------------
get_registration_info_by_device_id_test(doc) ->
    ["sc_push_reg_api:get_registration_info_by_device_id/1 should"
     "get the correct reg info for a single device ID"];
get_registration_info_by_device_id_test(suite) ->
    [];
get_registration_info_by_device_id_test(Config) ->
    RegPL1 = value(registration, Config),
    ok = sc_push_reg_api:register_id(RegPL1),
    NewTag = <<"my second tag">>,
    NewDeviceID = <<"my second device id">>,
    RegPL2 = lists:foldl(fun({K, _} = KV, Acc) ->
                            lists:keyreplace(K, 1, Acc, KV)
                         end, RegPL1, [{device_id, NewDeviceID},
                                       {tag, NewTag}]),
    ok = sc_push_reg_api:register_id(RegPL2),

    DevID1 = sc_util:to_bin(value(device_id, RegPL1)),
    DevID2 = sc_util:to_bin(value(device_id, RegPL2)),

    [NewRegPL1] = sc_push_reg_api:get_registration_info_by_device_id(DevID1),
    [NewRegPL2] = sc_push_reg_api:get_registration_info_by_device_id(DevID2),

    NewDevID1 = value(device_id, NewRegPL1),
    NewDevID1 = DevID1,
    NewDevID2 = value(device_id, NewRegPL2),
    NewDevID2 = DevID2,

    ct:pal("Got reginfo for ID ~p:~n~p", [NewDevID1, NewRegPL1]),
    ct:pal("Got reginfo for ID ~p:~n~p", [NewDevID2, NewRegPL2]),

    IDs = [DevID1, DevID2],
    [ok = sc_push_reg_api:deregister_device_id(ID) || ID <- IDs],
    ct:pal("Deregistered IDs ~p~n", [IDs]).

%%--------------------------------------------------------------------
get_registration_info_not_found_test(doc) ->
    ["sc_push_reg_api:get_registration_info/1 should not find this reg info"];
get_registration_info_not_found_test(suite) ->
    [];
get_registration_info_not_found_test(Config) ->
    FakeTag = <<"$$Completely bogus tag$$">>,
    notfound = sc_push_reg_api:get_registration_info(FakeTag),
    ct:pal("Got expected 'notfound' result for tag ~p~n", [FakeTag]),
    Config.

%%--------------------------------------------------------------------
get_registration_info_by_id_not_found_test(doc) ->
    ["sc_push_reg_api:get_registration_info_by_id/1 should not find this reg info"];
get_registration_info_by_id_not_found_test(suite) ->
    [];
get_registration_info_by_id_not_found_test(Config) ->
    FakeID = sc_push_reg_api:make_id(<<"Bogus ID">>, <<"Junk tag">>),
    notfound = sc_push_reg_api:get_registration_info_by_id(FakeID),
    ct:pal("Got expected 'notfound' result for ID ~p~n", [FakeID]),
    Config.

%%--------------------------------------------------------------------
update_last_invalid_test(doc) ->
    ["sc_push_reg_api:update_invalid_timestamp_by_svc_tok/2",
     "should update the last_invalid_on timestamp."];
update_last_invalid_test(suite) ->
    [];
update_last_invalid_test(Config) ->
    RegPL = value(registration, Config),
    Result = sc_push_reg_api:register_id(RegPL),
    ct:pal("register_id returned ~p~n", [Result]),
    ok = Result,
    ct:pal("Registered ~p~n", [RegPL]),
    TimestampMs = erlang:system_time(milli_seconds),
    SvcTok = svc_token_from_reg_props(RegPL),
    ok = sc_push_reg_api:update_invalid_timestamp_by_svc_tok(SvcTok,
                                                             TimestampMs),

    [NewRegPL] = sc_push_reg_api:get_registration_info_by_svc_tok(SvcTok),
    StoredTs = value(last_invalid_on, NewRegPL),
    ?assertEqual(StoredTs, from_posix_time_ms(TimestampMs)),

    deregister_id(RegPL).

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

%%====================================================================
%% Internal helper functions
%%====================================================================
deregister_id(RegPL) ->
    ID = id_from_reg_props(RegPL),
    ok = sc_push_reg_api:deregister_id(ID),
    ct:pal("Deregistered ID ~p~n", [ID]).

deregister_ids(RegPLs) ->
    IDs = [id_from_reg_props(PL) || PL <- RegPLs],
    ok = sc_push_reg_api:deregister_ids(IDs),
    ct:pal("Deregistered IDs ~p~n", [IDs]).

id_from_reg_props(RegPL) ->
    DeviceID = value(device_id, RegPL),
    Tag = value(tag, RegPL),
    sc_push_reg_api:make_id(DeviceID, Tag).

svc_token_from_reg_props(RegPL) ->
    Svc = value(service, RegPL),
    Token = value(token, RegPL),
    sc_push_reg_api:make_svc_tok(Svc, Token).

%%====================================================================
%% General helper functions
%%====================================================================
value(Key, Config) when is_list(Config) ->
    V = proplists:get_value(Key, Config),
    ?assertMsg(V =/= undefined, "Required key missing: ~p~n", [Key]),
    V.

make_n_reg_ids(N) ->
    [make_reg_id_n(Int) || Int <- lists:seq(1, N)].

%% "dev" is no longer supported as a dist type.
make_reg_id_n(N) ->
    sc_push_reg_db:make_sc_push_props(oneof([apns, gcm]),
                                      make_binary(<<"tok">>, N),
                                      make_binary(<<"some_uuid">>, N),
                                      make_binary(<<"tag">>, N),
                                      make_binary(<<"app_id">>, N),
                                      <<"prod">>,
                                      erlang:timestamp()
                                    ).

make_binary(<<BinPrefix/binary>>, N) when is_integer(N), N >= 0 ->
    <<BinPrefix/binary, $_, (sc_util:to_bin(N))/binary>>.

oneof([_|_] = L) ->
    lists:nth(random:uniform(length(L)), L).

reg_pls_equal([], []) ->
    true;
reg_pls_equal(PLs1, PLs2) ->
    sorted_reg_pls_equal(lists:sort(PLs1), lists:sort(PLs2)).

sorted_reg_pls_equal([PL1|PLs1], [PL2|PLs2]) ->
    case reg_pl_equal(PL1, PL2) of
        true ->
            sorted_reg_pls_equal(PLs1, PLs2);
        false ->
            throw({unequal_proplists, PL1, PL2})
    end;
sorted_reg_pls_equal([], []) ->
    true;
sorted_reg_pls_equal(PLs1, PLs2) ->
    throw({unequal_list_of_proplists, PLs1, PLs2}).

%% Don't compare modified because those are guaranteed to be changed
%% every time the record is written.
reg_pl_equal(PL1, PL2) ->
    lists:all(fun(K) -> proplists:get_value(K, PL1) =:= proplists:get_value(K, PL2) end,
              [service, token, tag, app_id, dist, id]).

%%--------------------------------------------------------------------
from_posix_time_ms(TimestampMs) ->
    sc_push_reg_db:from_posix_time_ms(TimestampMs).

%%--------------------------------------------------------------------
db_create(Config) ->
    DBInfo = value(dbinfo, Config),
    DB = maps:get(db, DBInfo),
    db_create(DB, DBInfo, Config).

db_create(mnesia, _DBInfo, Config) ->
    PrivDir = value(priv_dir, Config), % Standard CT variable
    MnesiaDir = filename:join(PrivDir, "mnesia"),
    ok = application:set_env(mnesia, dir, MnesiaDir),
    db_destroy(mnesia, _DBInfo, Config),
    ok = mnesia:create_schema([node()]);
db_create(DB, DBInfo, Config) ->
    db_create(mnesia, DBInfo, Config),
    clear_external_db(DB, DBInfo, Config).

%%--------------------------------------------------------------------
db_destroy(Config) ->
    DBInfo = value(dbinfo, Config),
    DB = maps:get(db, DBInfo),
    db_destroy(DB, DBInfo, Config).

db_destroy(mnesia, _DBInfo, _Config) ->
    mnesia:stop(),
    ok = mnesia:delete_schema([node()]);
db_destroy(DB, DBInfo, Config) ->
    db_destroy(mnesia, DBInfo, Config),
    clear_external_db(DB, DBInfo, Config).

%%--------------------------------------------------------------------
clear_external_db(postgres, _DBInfo, Config) ->
    ConnParams = db_config(postgres, Config),
    Tables = ["scpf.push_tokens"],
    {ok, Conn} = epgsql:connect(ConnParams),
    lists:foreach(fun(Table) ->
                          {ok, _} = epgsql:squery(Conn, "delete from " ++ Table)
                  end, Tables),
    ok = epgsql:close(Conn).

%%--------------------------------------------------------------------
db_pools(#{db := DB, mod := DBMod}, Config) ->
    [
     {sc_push_reg_pool, % name
      [ % sizeargs
       {size, 10},
       {max_overflow, 20}
      ],
      [ % workerargs
       {db_mod, DBMod},
       {db_config, db_config(DB, Config)}
      ]}
    ].

%%--------------------------------------------------------------------
db_config(DB, Config) ->
    maps:get(DB, value(connect_info, Config), []).

