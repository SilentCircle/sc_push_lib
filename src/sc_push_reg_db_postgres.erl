%%% ==========================================================================
%%% Copyright 2015-2017 Silent Circle
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%% ==========================================================================

-module(sc_push_reg_db_postgres).

%% Causing warnings (why???)
%%-behavior(sc_push_reg_db).

%% sc_push_reg_db callbacks
-export([
         db_init/1,
         db_info/1,
         db_terminate/1,
         all_reg/1,
         all_registration_info/1,
         check_id/2,
         check_ids/2,
         create_tables/2,
         delete_push_regs_by_device_ids/2,
         delete_push_regs_by_ids/2,
         delete_push_regs_by_svc_toks/2,
         delete_push_regs_by_tags/2,
         update_invalid_timestamps_by_svc_toks/2,
         get_registration_info_by_device_id/2,
         get_registration_info_by_id/2,
         get_registration_info_by_svc_tok/2,
         get_registration_info_by_tag/2,
         is_valid_push_reg/2,
         reregister_ids/2,
         reregister_svc_toks/2,
         save_push_regs/2
        ]).

%% Internal functions
-export([
         lookup_reg_device_id/2,
         lookup_reg_id/2,
         lookup_svc_tok/2,
         lookup_reg_tag/2
        ]).

-include("sc_push_lib.hrl").
-include_lib("epgsql/include/epgsql.hrl").

-ifndef(NO_SCHEMA).
-define(DB_SCHEMA, "scpf").
-define(DB_SCHEMA_PREFIX, ?DB_SCHEMA ".").
-else.
-define(DB_SCHEMA_PREFIX, "").
-endif.

-define(DB_PUSH_TOKENS_TBL_BASE, "push_tokens").
-define(DB_PUSH_TOKENS_TBL, ?DB_SCHEMA_PREFIX ?DB_PUSH_TOKENS_TBL_BASE).
-define(SPRDB, sc_push_reg_db).

-define(CTX, ?MODULE).
-record(?CTX, {conn,
               config,
               prep_qs = #{} % prepared queries, keyed by query name
              }).

-type db_ctx() :: #?CTX{}.
-type conn() :: epgsql:connection().
-type stmt() :: #statement{}.
-type col()  :: epqsql:column().
-type bind_param() :: epgsql:bind_param().

%%====================================================================
%% API
%%====================================================================
-spec db_init(Config) -> {ok, Context} | {error, Reason} when
      Config :: proplists:proplist(), Context :: db_ctx(),
      Reason :: term().
db_init(Config) when is_list(Config) ->
    Hostname = proplists:get_value(hostname, Config),
    Database = proplists:get_value(database, Config),
    Username = proplists:get_value(username, Config),
    Password = proplists:get_value(password, Config),

    case epgsql:connect(Hostname, Username, Password,
                        [{database, Database}]) of
        {ok, Conn} ->
            make_context(Conn, Config);
        {error, _Reason}=Error ->
            Error
    end.

%%--------------------------------------------------------------------
-spec db_info(Ctx) -> Props when
      Ctx :: db_ctx(), Props :: proplists:proplist().
db_info(Ctx) ->
    [{conn, Ctx#?CTX.conn},
     {config, Ctx#?CTX.config},
     {extra, Ctx#?CTX.prep_qs}].

%%--------------------------------------------------------------------
-spec db_terminate(db_ctx()) -> term().
db_terminate(#?CTX{conn=Conn}) ->
    epgsql:close(Conn).

%%--------------------------------------------------------------------
%% @doc Return a list of property lists of all registrations.
%% @deprecated For debug only
-spec all_registration_info(db_ctx()) -> [sc_types:reg_proplist()].
all_registration_info(#?CTX{conn=Conn}) ->
    db_all_regs(Conn).

%%--------------------------------------------------------------------
%% @doc Return a list of all push registration records.
%% @deprecated For debug only.
-spec all_reg(db_ctx()) -> ?SPRDB:push_reg_list().
all_reg(#?CTX{conn=Conn}) ->
    db_all_regs(Conn).

%%--------------------------------------------------------------------
%% @doc Check registration id key.
-spec check_id(#?CTX{}, ?SPRDB:reg_id_key()) -> ?SPRDB:reg_id_key().
check_id(_Ctx, ID) ->
    case ID of
        {<<_, _/binary>>, <<_, _/binary>>} ->
           ID;
       _ ->
           throw({bad_reg_id, ID})
    end.

%%--------------------------------------------------------------------
%% @doc Check multiple registration id keys.
-spec check_ids(db_ctx(), ?SPRDB:reg_id_keys()) -> ?SPRDB:reg_id_keys().
check_ids(Ctx, IDs) when is_list(IDs) ->
    [check_id(Ctx, ID) || ID <- IDs].

%%--------------------------------------------------------------------
create_tables(#?CTX{}, _Config) ->
    ok.

%%--------------------------------------------------------------------
%% @doc Delete push registrations by device ids
-spec delete_push_regs_by_device_ids(db_ctx(), [binary()]) ->
    ok | {error, term()}.
delete_push_regs_by_device_ids(#?CTX{conn=Conn},
                               DeviceIDs) when is_list(DeviceIDs) ->
    % In our pg db, device_ids are last_xscdevid.
    {ok, _N} = pq(Conn, <<"del_regs_by_device_ids">>, [DeviceIDs]),
    ok.

%%--------------------------------------------------------------------
%% @doc Delete push registrations by internal registration id.
-spec delete_push_regs_by_ids(db_ctx(), ?SPRDB:reg_id_keys()) -> ok | {error, term()}.
delete_push_regs_by_ids(#?CTX{conn=Conn, prep_qs=QMap}, IDs) ->
    Stmt = maps:get(<<"del_reg_by_id">>, QMap),
    Batch = [{Stmt, [DeviceID, Tag]} || {DeviceID, Tag} <- IDs],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by service-token.
-spec delete_push_regs_by_svc_toks(db_ctx(), [?SPRDB:svc_tok_key()]) ->
    ok | {error, term()}.
delete_push_regs_by_svc_toks(#?CTX{conn=Conn,
                                   prep_qs=QMap},
                             SvcToks) when is_list(SvcToks) ->
    Stmt = maps:get(<<"del_reg_by_svc_tok">>, QMap),
    Batch = [{Stmt, [svc_to_type(Svc), Tok]} || {Svc, Tok} <- SvcToks],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by tags.
-spec delete_push_regs_by_tags(db_ctx(), [binary()]) -> ok | {error, term()}.
delete_push_regs_by_tags(#?CTX{conn=Conn,
                               prep_qs=QMap}, Tags) when is_list(Tags) ->
    Stmt = maps:get(<<"del_reg_by_tag">>, QMap),
    Batch = [{Stmt, [Tag]} || Tag <- Tags],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Update push registration last_invalid timestmap by service-token.
-spec update_invalid_timestamps_by_svc_toks(db_ctx(), [{?SPRDB:svc_tok_key(),
                                                        non_neg_integer()}]) ->
    ok | {error, term()}.
update_invalid_timestamps_by_svc_toks(#?CTX{conn=Conn,
                                            prep_qs=QMap},
                                      SvcToksTs) when is_list(SvcToksTs) ->
    Stmt = maps:get(<<"update_invalid_ts_svc_tok">>, QMap),
    Batch = [{Stmt, [posix_ms_to_pg_datetime(TS), svc_to_type(Svc), Tok]}
             || {{Svc, Tok}, TS} <- SvcToksTs],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Get registration information by device id.
-spec get_registration_info_by_device_id(db_ctx(), binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_device_id(#?CTX{conn=Conn}, DeviceID) ->
    get_registration_info_impl(Conn, DeviceID, fun lookup_reg_device_id/2).

%%--------------------------------------------------------------------
%% @doc Get registration information by unique id.
%% @see sc_push_reg_db:make_id/2
-spec get_registration_info_by_id(db_ctx(), ?SPRDB:reg_id_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_id(#?CTX{conn=Conn}, ID) ->
    get_registration_info_impl(Conn, ID, fun lookup_reg_id/2).

%%--------------------------------------------------------------------
%% @doc Get registration information by service-token.
%% @see sc_push_reg_api:make_svc_tok/2
-spec get_registration_info_by_svc_tok(db_ctx(), ?SPRDB:svc_tok_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_svc_tok(#?CTX{conn=Conn}, {_Service, _Token} = SvcTok) ->
    get_registration_info_impl(Conn, SvcTok, fun lookup_svc_tok/2).

%%--------------------------------------------------------------------
%% @doc Get registration information by tag.
-spec get_registration_info_by_tag(db_ctx(), binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(#?CTX{conn=Conn}, Tag) ->
    get_registration_info_impl(Conn, Tag, fun lookup_reg_tag/2).

%%--------------------------------------------------------------------
%% @doc Is push registration proplist valid?
-spec is_valid_push_reg(db_ctx(), sc_types:proplist(atom(), term())) -> boolean().
is_valid_push_reg(#?CTX{}, PL) ->
    try make_upsert_params(PL) of
        _ -> true
    catch _:_ -> false
    end.

%%--------------------------------------------------------------------
%% @doc Save a list of push registrations.
-spec save_push_regs(db_ctx(), [sc_types:reg_proplist(), ...]) -> ok | {error, term()}.
save_push_regs(#?CTX{conn=Conn, prep_qs=QMap}, ListOfProplists) ->
    Stmt = maps:get(<<"call_upsert_func">>, QMap),
    Batch = [{Stmt, make_upsert_params(PL)} || PL <- ListOfProplists],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Re-register invalidated tokens
-spec reregister_ids(db_ctx(), [{?SPRDB:reg_id_key(), binary()}]) -> ok.
reregister_ids(#?CTX{conn=Conn, prep_qs=QMap}, IDToks) when is_list(IDToks) ->
    Stmt = maps:get(<<"reregister_id">>, QMap),
    Batch = [{Stmt, [NewTok, DevId, Tag]}
             || {{DevId, Tag}, NewTok} <- IDToks],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Re-register invalidated tokens by svc_tok
-spec reregister_svc_toks(db_ctx(), [{?SPRDB:svc_tok_key(), binary()}]) -> ok.
reregister_svc_toks(#?CTX{conn=Conn,
                          prep_qs=QMap}, SvcToks) when is_list(SvcToks) ->
    Stmt = maps:get(<<"reregister_svc_tok">>, QMap),
    Batch = [{Stmt, [NewTok, svc_to_type(Svc), Tok]}
             || {{Svc, Tok}, NewTok} <- SvcToks],
    do_batch(Conn, Batch).

%%====================================================================
%% Internal functions
%%====================================================================

%%--------------------------------------------------------------------
make_context(Conn, Config) ->
    try
        {ok, PrepQs} = prepare_statements(Conn),
        {ok, #?CTX{conn=Conn, config=Config, prep_qs=PrepQs}}
    catch
        _:Error ->
            (catch epqsql:close(Conn)),
            Error
    end.

%%--------------------------------------------------------------------
prepare_statements(Conn) ->
    PTQueries = push_tokens_queries(?DB_PUSH_TOKENS_TBL),
    case prepared_queries(Conn, PTQueries) of
        {PrepQs, []} ->
            handle_error(pq(Conn, <<"create_upsert_func">>, [])),
            {ok, maps:from_list([{S#statement.name, S} || S <- PrepQs])};
        {_, Errors} ->
            {error, Errors}
    end.

%%--------------------------------------------------------------------
%% Database functions
%%--------------------------------------------------------------------
%%--------------------------------------------------------------------
make_upsert_params([_|_]=PL) ->
    ServiceS = sc_util:to_list(sc_util:val(service, PL, "apns")),
    Type = svc_to_type(sc_util:to_atom(sc_util:req_s(ServiceS))),
    Token = sc_util:to_bin(sc_util:req_val(token, PL)),
    XscDevId = sc_util:to_bin(sc_util:req_val(device_id, PL)),
    UUID = sc_util:to_bin(sc_util:val(tag, PL, "")),
    AppId = sc_util:to_bin(sc_util:req_val(app_id, PL)),
    % (uuid_ text, type_ text, token_ text, appname_ text, xscdevid_ text)
    [UUID, Type, Token, AppId, XscDevId].

%%--------------------------------------------------------------------
-ifdef(USE_upsert_row_txn).
upsert_row_txn(Conn, RegProps) ->
    Tag = sc_util:req_val(tag, RegProps),
    Service = sc_util:req_val(service, RegProps),
    Type = svc_to_type(Service),
    Token = sc_util:req_val(token, RegProps),
    AppId = sc_util:req_val(app_id, RegProps),
    DeviceId = sc_util:req_val(device_id, RegProps),

    fun(C) ->
            {ok, _, Rows} = epq(C, <<"lookup_one_reg">>,
                                [Tag, Type, Token, AppId]),

            {Q, Args} = case Rows of
                              [] -> % insert
                                  {<<"insert_reg">>, [Tag, Type, Token,
                                                      AppId, DeviceId]};
                              [{RowId}] when is_integer(RowId) ->
                                  {<<"update_reg">>, [Tag, Type, Token,
                                                      AppId, DeviceId,
                                                      RowId]
                          end,
            epq(C, Q, Args)
    end.
-endif.

%%--------------------------------------------------------------------
%% For debugging only - if called on large db, unhappy days ahead.
-spec db_all_regs(term()) -> ?SPRDB:push_reg_list().
db_all_regs(Conn) ->
    do_reg_pquery(Conn, <<"all_regs">>, []).

%%--------------------------------------------------------------------
-spec lookup_reg_id(conn(), ?SPRDB:reg_id_key()) -> ?SPRDB:push_reg_list().
lookup_reg_id(Conn, {DevID, Tag}) ->
    do_reg_pquery(Conn, <<"lookup_reg_id">>, [DevID, Tag]).

%%--------------------------------------------------------------------
-spec lookup_reg_device_id(conn(), binary()) -> ?SPRDB:push_reg_list().
lookup_reg_device_id(Conn, DevID) when is_binary(DevID) ->
    do_reg_pquery(Conn, <<"lookup_reg_device_id">>, [DevID]).

%%--------------------------------------------------------------------
-spec lookup_reg_tag(conn(), binary()) -> ?SPRDB:push_reg_list().
lookup_reg_tag(Conn, Tag) when is_binary(Tag) ->
    do_reg_pquery(Conn, <<"lookup_reg_tag">>, [Tag]).

%%--------------------------------------------------------------------
-spec lookup_svc_tok(conn(), ?SPRDB:svc_tok_key()) -> ?SPRDB:push_reg_list().
lookup_svc_tok(Conn, {Svc, Tok}) when is_atom(Svc), is_binary(Tok) ->
    do_reg_pquery(Conn, <<"lookup_reg_svc_tok">>, [svc_to_type(Svc), Tok]).

%%--------------------------------------------------------------------
get_registration_info_impl(Conn, Key, Lookup) when is_function(Lookup, 2) ->
    case Lookup(Conn, Key) of
        [_|_] = Regs ->
            Regs;
        [] ->
            notfound
    end.

%%--------------------------------------------------------------------
do_reg_pquery(Conn, QueryName, Args) ->
    case pq(Conn, QueryName, Args) of
        {error, _}=Error ->
            Error;
        {ok, Count} when is_integer(Count) ->
            [];
        {ok, Maps} when is_list(Maps) ->
            push_reg_maps_to_props(Maps);
        {ok, _Count, Maps} ->
            push_reg_maps_to_props(Maps)
    end.

%%--------------------------------------------------------------------
push_reg_maps_to_props(Maps) ->
    [sc_push_reg_db:make_sc_push_props(get_service(M),
                                       get_token(M),
                                       get_device_id(M),
                                       get_tag(M),
                                       get_app_id(M),
                                       <<"prod">>,
                                       get_modified(M),
                                       get_last_invalid_on(M),
                                       get_created_on(M)
                                       ) || M <- Maps].

%%--------------------------------------------------------------------
pq(Conn, QueryName, Args) ->
    case epq(Conn, QueryName, Args) of
        {ok, Count} when is_integer(Count) ->
            {ok, Count};
        {ok, Columns, Rows} ->
            {ok, pg2scpf_maps(Columns, Rows)};
        {ok, Count, Columns, Rows} ->
            {ok, Count, pg2scpf_maps(Columns, Rows)};
        {error, #error{}=E} ->
            {error, pg2scpf_err(E)}
    end.

%%--------------------------------------------------------------------
-compile({inline, [{epq, 3}]}).
epq(C, Q, Args) ->
    epgsql:prepared_query(C, Q, Args).

%%--------------------------------------------------------------------
-spec do_batch(Conn, Batch) -> Result when
      Conn :: conn(), Batch :: [{stmt(), [bind_param()]}],
      Result :: ok | {error, term()}.
do_batch(Conn, Batch) ->
    {ok, [], []} = epgsql:squery(Conn, "BEGIN"),
    L = epgsql:execute_batch(Conn, Batch),
    case lists:partition(fun(T) ->
                                 element(1, T) =:= ok
                         end, L) of
        {_, []} -> % All good
            {ok, [], []} = epgsql:squery(Conn, "COMMIT"),
            ok;
        {_, Errs} ->
            epqsql:squery(Conn, "ROLLBACK"),
            {error, Errs}
    end.

%%--------------------------------------------------------------------
-spec svc_to_type(Svc) -> Type when
      Svc :: atom(), Type :: binary().
svc_to_type(apns) -> <<"iOS">>;
svc_to_type(gcm)  -> <<"Android">>;
svc_to_type(Atom) -> sc_util:to_bin(Atom).

%%--------------------------------------------------------------------
-spec type_to_svc(Type) -> Svc when
      Type :: binary(), Svc :: atom().
type_to_svc(<<"iOS">>)     -> apns;
type_to_svc(<<"Android">>) -> gcm;
type_to_svc(Val)           -> sc_util:to_atom(Val). %% FIXME: Potential DoS

%%--------------------------------------------------------------------
-spec pg2scpf_maps(Columns, Rows) -> Result when
      Columns :: [col()], Rows :: list(), Result :: [map()].
pg2scpf_maps(Columns, Rows) when is_list(Rows) ->
    NumberedCols = lists:zip(Columns, lists:seq(1, length(Columns))),
    [pg2scpf(NumberedCols, Row) || Row <- Rows].


%%--------------------------------------------------------------------
-spec pg2scpf(NumberedCols, Row) -> Map when
      NumberedCols :: [{Col, ColNo}], Row :: tuple(),
      Col :: col(), ColNo :: pos_integer(), Row :: tuple(),
      Map :: map().
pg2scpf(NumberedCols, Row) when is_list(NumberedCols), is_tuple(Row) ->
    maps:from_list(lists:foldl(fun({#column{name=Name, type=T}, N}, Acc) ->
                                       [pg2api(Name, T, element(N, Row)) | Acc]
                               end, [], NumberedCols)).

%%--------------------------------------------------------------------
pg2api(Name, Type, Val) ->
    ApiName = pgname2api(Name),
    ApiVal = pgtype2api(Type, Val),
    {ApiName, pg2api_xlate(ApiName, ApiVal)}.


%%--------------------------------------------------------------------
pg2api_xlate(service, <<Svc/binary>>) ->
    type_to_svc(Svc);
pg2api_xlate(_Name, Val) ->
    Val.

%%--------------------------------------------------------------------
pg2scpf_err(#error{severity=S,
                   code=C,
                   codename=CN,
                   message=Msg,
                   extra=Extra}) ->
    {db_error, db, [{message, Msg},
                    {severity, S},
                    {code, C},
                    {codename, CN},
                    {extra, Extra}]};
pg2scpf_err(Other) ->
    {db_error, other, Other}.


%%--------------------------------------------------------------------
get_tag(#{tag := V})                         -> V.
get_service(#{service := V})                 -> V.
get_token(#{token := V})                     -> V.
get_app_id(#{app_id := V})                   -> V.
get_created_on(#{created_on := V})           -> V.
get_modified(#{modified := V})               -> V.
get_last_invalid_on(#{last_invalid_on := V}) -> V.
get_device_id(#{device_id := V})             -> V.

-compile({inline, [
                   {get_tag, 1},
                   {get_service, 1},
                   {get_token, 1},
                   {get_app_id, 1},
                   {get_created_on, 1},
                   {get_modified, 1},
                   {get_last_invalid_on, 1},
                   {get_device_id, 1}
                  ]}).

%%--------------------------------------------------------------------
pgname2api(<<"uuid">>)             -> tag;
pgname2api(<<"type">>)             -> service;
pgname2api(<<"token">>)            -> token;
pgname2api(<<"appname">>)          -> app_id;
pgname2api(<<"created_on">>)       -> created_on;
pgname2api(<<"last_seen_on">>)     -> modified;
pgname2api(<<"last_invalid_on">>)  -> last_invalid_on;
pgname2api(<<"last_xscdevid">>)    -> device_id.

%%--------------------------------------------------------------------
%% Formats by example returned by epgsql for each data type
%%
%% The one thing we need to be concerned with here is the
%% timestamp format, which our API expects to be
%% returned in erlang:timestamp() format but is given in
%% {Date, Time.Microseconds} format.
%%
%% Type               Value
%% ----               -----
%% <any if null>      null
%% int4               1
%% int8               100
%% int8               1
%% bit                <<"11110000111100001111000011110000">>
%% varbit             <<"11111111">>
%% bool               true
%% bool               false
%% box                <<"(1,1),(0,0)">>
%% bytea              <<"Êþº¾">>
%% bpchar             <<"character32                     ">>
%% varchar            <<"character_varying32">>
%% cidr               {{192,168,100,128},25}
%% circle             <<"<(0,0),1>">>
%% date               {2017,6,7}
%% float8             3.141592653589793
%% inet               {192,168,1,1}
%% int4               102
%% {array,int4}       [[1,2,3],[4,5,6],[7,8,9]]
%% interval           {{0,7,6.123456},8,129}
%% interval           {{0,0,0.0},0,108}
%% interval           {{0,0,0.0},0,8}
%% interval           {{0,0,0.0},7,0}
%% interval           {{6,0,0.0},0,0}
%% interval           {{0,5,0.0},0,0}
%% interval           {{0,0,4.123456},0,0}
%% interval           {{0,0,0.0},0,129}
%% interval           {{6,0,0.0},7,0}
%% interval           {{6,5,0.0},7,0}
%% interval           {{6,5,4.234567},7,0}
%% interval           {{10,59,0.0},0,0}
%% interval           {{10,59,2.345678},0,0}
%% interval           {{0,10,15.123456},0,0}
%% json               <<"{\"product\": \"PostgreSQL\", \"version\": 9.4, \"jsonb\":false, \"a\":[1,2,3]}">>
%% jsonb              <<"{\"a\": [1, 2, 3], \"jsonb\": true, \"product\": \"PostgreSQL\", \"version\": 9.4}">>
%% line               <<"{1,-1,0}">>
%% lseg               <<"[(0,0),(0,1)]">>
%% macaddr            <<"08:00:2b:01:02:03">>
%% cash               <<"$1,234,567.89">>
%% numeric            <<"1234567890.0123456789">>
%% path               <<"((0,1),(1,2),(2,3))">>
%% {unknown_oid,3220} <<"ABCD/CDEF">>
%% point              {10.0,10.0}
%% polygon            <<"((0,0),(0,1),(1,1),(1,0))">>
%% float4             2.718280076980591
%% int2               42
%% int2               1
%% text               <<"No man is an iland, entire of itself;">>
%% time               {4,5,6.345678}
%% timestamp          {{2017,6,5},{4,5,6.789}}
%% timestamptz        {{2017,6,5},{8,5,6.789}}
%% tsquery            <<"'fat' & ( 'rat' | 'cat' )">>
%% tsvector           <<"'a' 'and' 'ate' 'cat' 'fat' 'mat' 'on' 'rat' 'sat'">>
%% {unknown_oid,2970} null
%% uuid               <<"1a54f33b-f891-45f6-bf8d-5e6fd36af617">>
%% xml                <<"<html><head/><body/></html>">>
-spec pgtype2api(PGType, PGVal) -> APIVal when
      PGType :: atom() | {array, atom()} | {unknown_oid, integer()},
      PGVal :: term(), APIVal :: term().

pgtype2api(timestamp,   {{_,_,_},{_,_,_}}=DateTime) -> datetime_to_now(DateTime);
pgtype2api(timestamptz, {{_,_,_},{_,_,_}}=DateTime) -> datetime_to_now(DateTime);
pgtype2api(_,           null) -> undefined;
pgtype2api(_,           Val) -> Val.

%%--------------------------------------------------------------------
%% Get time since the epoch in seconds, and derive microseconds from the
%% seconds value if it is a floating point value.
datetime_to_now({{_,_,_}=Date, {H,M,FracSecs}}) ->
    S = erlang:trunc(FracSecs),
    Micros = erlang:trunc((FracSecs - S) * 1000000),
    POSIXSecs = calendar:datetime_to_gregorian_seconds({Date,{H,M,S}}) -
                calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    {POSIXSecs div 1000000, POSIXSecs rem 1000000, Micros}.

%%--------------------------------------------------------------------
posix_ms_to_pg_datetime(PosixMs) ->
    PosixSecs = PosixMs div 1000,
    Micros = PosixMs rem 1000 * 1000,
    TS = {PosixSecs div 1000000, PosixSecs rem 1000000, Micros},
    {Date, {H,M,S}} = calendar:now_to_universal_time(TS),
    {Date, {H, M, S + (Micros / 1000000.0)}}.

%%--------------------------------------------------------------------
-spec prepared_queries(Conn, Queries) -> Result when
      Conn :: epgsql:connection(),
      Queries :: [{StmtName, QueryIoList}], StmtName :: iolist(),
      QueryIoList :: iolist(),
      Result :: {Stmts, Errs}, Stmts :: [stmt()], Errs :: [{error, Reason}],
      Reason :: epgsql:query_error().
prepared_queries(Conn, Queries) ->
    {S, E} = lists:foldl(fun({QName, Q}, {Stmts, Errs}) ->
                        case prepare(Conn, QName, Q) of
                            {ok, Stmt} ->
                                {[Stmt|Stmts], Errs};
                            {error, Err} ->
                                {Stmts, [Err|Errs]}
                        end
                end, {[], []}, Queries),
    lager:info("Queries prepared successfully: ~B; failed: ~B",
               [length(S), length(E)]),
    {S, E}.


%%--------------------------------------------------------------------
-compile({inline, [{prepare,3}]}).
prepare(Conn, QueryName, Query) ->
    lager:debug("Preparing query ~s: [~s]",
                [QueryName, list_to_binary(Query)]),
    epgsql:parse(Conn, QueryName, Query, []).

%%--------------------------------------------------------------------
push_tokens_queries(Tab) ->
    Tbl = sc_util:to_bin(Tab),
    Cols = push_tokens_colnames_iolist(),
    [{<<"lookup_one_reg">>,
      [<<"select id from ">>, Tbl,
       <<" where uuid = $1 and type = $2 and token = $3 and appname = $4">>,
       <<" limit 1">>]},
     {<<"all_regs">>, make_select_all_query(Tbl, Cols)},
     {<<"lookup_reg_id">>,
      make_lookup_query(Tbl, Cols, <<"last_xscdevid = $1 and uuid = $2">>)},
     {<<"lookup_reg_device_id">>,
      make_lookup_query(Tbl, Cols, <<"last_xscdevid = $1">>)},
     {<<"lookup_reg_tag">>,
      make_lookup_query(Tbl, Cols, <<"uuid = $1">>)},
     {<<"lookup_reg_svc_tok">>,
      make_lookup_query(Tbl, Cols, <<"type = $1 and token = $2">>)},
     {<<"del_regs_by_device_ids">>,
      make_delete_query(Tbl, <<"last_xscdevid = any($1)">>)},
     {<<"del_reg_by_id">>,
      make_delete_query(Tbl, <<"last_xscdevid = $1 and uuid = $2">>)},
     {<<"del_reg_by_svc_tok">>,
      make_delete_query(Tbl, <<"type = $1 and token = $2">>)},
     {<<"del_reg_by_tag">>, make_delete_query(Tbl, <<"uuid = $1">>)},
     {<<"update_invalid_ts_svc_tok">>,
      [<<"update ">>, Tbl, <<" set last_invalid_on = $1">>,
       $\s, <<"where type = $2 and token = $3">>]},
     {<<"reregister_id">>,
      [<<"update ">>, Tbl, <<" set token = $1">>,
       <<" where last_xscdevid = $2 and uuid = $3">>]},
     {<<"reregister_svc_tok">>,
      [<<"update ">>, Tbl, <<" set token = $1">>,
       <<" where type = $2 and token = $3">>]},
     {<<"insert_reg">>,
      [<<"insert into ">>, Tbl,
       <<" (uuid, type, token, appname, last_xscdevid) ">>,
       <<" values ($1, $2, $3, $4, $5)">>]},
     {<<"update_reg">>,
      [<<"update ">>, Tbl,
       <<" set uuid = $1, type = $2, token = $3,">>,
       <<" appname = $4, last_xscdevid = $5, last_seen_on = now() ">>,
       <<" where id = $6">>]},
     {<<"delete_upsert_func">>, delete_upsert_func(schema_prefix())},
     {<<"create_upsert_func">>,
      make_upsert_function_query(Tbl, schema_prefix())},
     {<<"call_upsert_func">>, call_upsert_function(schema_prefix())}
    ].

%%--------------------------------------------------------------------
push_tokens_colnames() ->
    [
     <<"uuid">>,
     <<"type">>,
     <<"token">>,
     <<"appname">>,
     <<"created_on">>,
     <<"last_seen_on">>,
     <<"last_invalid_on">>,
     <<"last_xscdevid">>
    ].

%%--------------------------------------------------------------------
push_tokens_colnames_iolist() ->
    bjoin(push_tokens_colnames(), <<",">>).

%%--------------------------------------------------------------------
bjoin(ListOfBinaries, <<Sep/binary>>) ->
    bjoin(ListOfBinaries, Sep, []).

%%--------------------------------------------------------------------
bjoin([<<B/binary>>], <<Sep/binary>>, Acc) ->
    bjoin([], Sep, [B | Acc]);
bjoin([<<B/binary>> | Rest], <<Sep/binary>>, Acc) ->
    bjoin(Rest, Sep, [Sep, B | Acc]);
bjoin([], <<_Sep/binary>>, Acc) ->
    lists:reverse(Acc).

%%--------------------------------------------------------------------
make_select_all_query(Tbl, Cols) ->
    [<<"select ">>, Cols, <<" from ">>, Tbl].

%%--------------------------------------------------------------------
make_lookup_query(Tbl, Cols, WhereCondition) ->
    [<<"select ">>, Cols, <<" from ">>, Tbl,
     <<" where ">>, WhereCondition].

%%--------------------------------------------------------------------
make_delete_query(Tbl, WhereCondition) ->
    [<<"delete from ">>, Tbl, <<" where ">>, WhereCondition].

%%--------------------------------------------------------------------
make_upsert_function_query(Tab, SchemaPrefix) ->
    [<<"create or replace function ">>, SchemaPrefix, <<"push_tokens_upsert">>,
     <<"(uuid_ text, type_ text, token_ text, appname_ text, xscdevid_ text)
            returns integer as $$
          declare
            r record;
          begin
            select a.id,
                a.last_seen_on < now() - interval '1 day' as needs_atime,
                a.last_xscdevid is null
                or a.last_xscdevid <> xscdevid_ as needs_xscdevid
                into r
              from ">>, Tab, <<" a
              where a.uuid = uuid_
                and a.type = type_
                and a.token = token_
                and a.appname = appname_
              limit 1;
            if not found then
              insert into ">>, Tab, <<" (uuid,type,token,appname,last_xscdevid)
                values (uuid_,type_,token_,appname_,xscdevid_);
              return 1;
            else
              if r.needs_atime or r.needs_xscdevid then
                update ">>, Tab, <<" set last_seen_on = now()
                  where id = r.id;
                if r.needs_xscdevid then
                  update ">>, Tab,
     <<" set last_xscdevid = xscdevid_
                    where id = r.id;
                  return 3;
                end if;
                return 2;
              end if;
            end if;
            return 0;
          end;
          $$ language plpgsql volatile strict;">>].

%%--------------------------------------------------------------------
delete_upsert_func(SchemaPrefix) ->
    [<<"drop function if exists ">>,
     SchemaPrefix, <<"push_tokens_upsert(text,text,text,text,text)">>].

%%--------------------------------------------------------------------
call_upsert_function(SchemaPrefix) ->
    [<<"select ">>, SchemaPrefix, <<"push_tokens_upsert($1, $2, $3, $4, $5)">>].

%%--------------------------------------------------------------------
schema_prefix() ->
    list_to_binary(?DB_SCHEMA_PREFIX).

%%--------------------------------------------------------------------
%-record(error, {
%    % see client_min_messages config option
%    severity :: debug | log | info | notice | warning | error | fatal | panic,
%    code :: binary(),
%    codename :: atom(),
%    message :: binary(),
%    extra :: [{severity | detail | hint | position | internal_position | internal_query
%               | where | schema_name | table_name | column_name | data_type_name
%               | constraint_name | file | line | routine,
%               binary()}]
%}).

handle_error({error, #error{}=E}) ->
    lager:error("~s", [pg_errstr(E)]),
    throw(E);
handle_error({error, {unsupported_auth_method, Method}}) -> % required auth method is unsupported
    erlang:error({db_unsupported_auth_method, Method});
handle_error({error, timeout}) -> % request timed out
    erlang:error(db_timeout);
handle_error({error, closed})  -> % connection was closed
    erlang:error(db_closed);
handle_error({error, sync_required}) -> % error occured and epgsql:sync must be called
    erlang:error(db_sync_required);
handle_error(NotAnError) ->
    NotAnError.

%%--------------------------------------------------------------------
pg_errstr(#error{}=E) ->
    io_lib:format("postgres[~p] ~p[~s]: ~s",
                  [E#error.severity, E#error.codename, E#error.code,
                   E#error.message]).

