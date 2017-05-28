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

-behavior(sc_push_reg_db).

%% sc_push_reg_db callbacks
-export([
         db_init/1,
         db_info/1,
         db_terminate/1,
         all_reg/1,
         all_registration_info/1,
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

-define(ROLE, pool_worker).

-ifndef(NO_SCHEMA).
-define(DB_SCHEMA, "scpf").
-define(DB_SCHEMA_PREFIX, ?DB_SCHEMA ".").
-else.
-define(DB_SCHEMA_PREFIX, "").
-endif.

-define(DB_PUSH_TOKENS_TBL_BASE, "push_tokens").
-define(DB_PUSH_TOKENS_TBL, ?DB_SCHEMA_PREFIX ?DB_PUSH_TOKENS_TBL_BASE).
-define(SPRDB, sc_push_reg_db).
-define(EPOCH_GREGORIAN_SECONDS, 62167219200). % Jan 1, 1970 00:00:00 GMT

-define(CTX, ?MODULE).
-record(?CTX, {conn          :: epgsql:connection(),
               config        :: proplists:proplist(),
               prep_qs = #{} :: map() % prepared queries, keyed by query name
              }).

-type ctx() :: #sc_push_reg_db_postgres{}.
-type stmt() :: #statement{}.
-type col()  :: #column{}.
-type pg_error() :: #error{}.

%% epgsql type aliases
-type conn() :: epgsql:connection().
-type bind_param() :: epgsql:bind_param().
-type equery_row() :: epgsql:equery_row().
-type row() :: equery_row().

-type query_name() :: string(). %% Why?? binary() actually does work, but...
-type cols() :: [col()].
-type rows() :: [row()].

-type other_error() :: {error, term()}.
-type scpf_error() :: {db_error, db, proplists:proplist()} |
                      {db_error, other, other_error()}.
-type reg_id_key() :: sc_push_reg_db:reg_id_key().
-type reg_id_keys() :: sc_push_reg_db:reg_id_keys().
-type push_reg_list() :: sc_push_reg_db:db_props_lookup_result().
-type svc_tok_key() :: sc_push_reg_db:svc_tok_key().
-type mult_svc_tok_ts() :: sc_push_reg_db:mult_svc_tok_ts().
-type reg_proplist() :: sc_types:reg_proplist().
-type nonempty_reg_proplists() :: [reg_proplist(), ...].

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% @doc Initialize the database connection.
%%
%% Return an opaque context for use with the other API calls.
%%
%% <dl>
%%  <dt>`Config'</dt><dd>A property list containing at least
%%  the following properties:
%%  <dl>
%%    <dt>`hostname :: string()'</dt><dd>Postgres host name</dd>
%%    <dt>`database :: string()'</dt><dd>Database name</dd>
%%    <dt>`username :: string()'</dt><dd>User (role) name</dd>
%%    <dt>`password :: string()'</dt><dd>User/role password</dd>
%%  </dl>
%%  </dd>
%%  <dt>`Context'</dt><dd>An opaque term returned to the caller.</dd>
%% </dl>
%% @end
%%--------------------------------------------------------------------
-spec db_init(Config) -> {ok, Context} | {error, Reason} when
      Config :: proplists:proplist(), Context :: ctx(),
      Reason :: term().
db_init(Config) when is_list(Config) ->
    connect(Config).

%%--------------------------------------------------------------------
%% @doc Get information about the database context passed in `Ctx'.
%%
%% Return a property list as follows:
%%
%% <dl>
%%   <dt>`conn :: pid()'</dt><dd>Postgres connection pid</dd>
%%   <dt>`config :: proplist()'</dt><dd>Value passed to db_init/1</dd>
%%   <dt>`extra :: term()'</dt>
%%    <dd>Extra information. This is currently a map of prepared statements,
%%    but may change without notice.</dd>
%% </dl>
%% @end
%%--------------------------------------------------------------------
-spec db_info(Ctx) -> Props when
      Ctx :: ctx(), Props :: proplists:proplist().
db_info(Ctx) ->
    [{conn, Ctx#?CTX.conn},
     {config, Ctx#?CTX.config},
     {extra, Ctx#?CTX.prep_qs}].

%%--------------------------------------------------------------------
%% @doc Terminate the database connection.
%% The return value has no significance.
%% @end
%%--------------------------------------------------------------------
-spec db_terminate(Ctx) -> Result when
      Ctx :: ctx(), Result :: ok.
db_terminate(#?CTX{conn=Conn}) ->
    epgsql:close(Conn).

%%--------------------------------------------------------------------
%% @private
%% @doc Return a list of property lists of all registrations.
%% @deprecated For debug only
%% @end
%%--------------------------------------------------------------------
-spec all_registration_info(Ctx) -> ListOfRegs when
      Ctx :: ctx(), ListOfRegs :: sc_push_reg_db:mult_reg_db_props().
all_registration_info(#?CTX{conn=Conn}) ->
    db_all_regs(Conn).

%%--------------------------------------------------------------------
%% @private
%% @doc Return a list of all push registration records.
%% @deprecated For debug only.
%% @end
%%--------------------------------------------------------------------
-spec all_reg(Ctx) -> ListOfRegs when
      Ctx :: ctx(), ListOfRegs :: sc_push_reg_db:mult_reg_db_props().
all_reg(#?CTX{conn=Conn}) ->
    db_all_regs(Conn).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by device ids.
%% @end
%%--------------------------------------------------------------------
-spec delete_push_regs_by_device_ids(Ctx, DeviceIds) -> Result when
      Ctx :: ctx(), DeviceIds :: [binary()], Result :: ok | {error, term()}.
delete_push_regs_by_device_ids(#?CTX{conn=Conn},
                               DeviceIDs) when is_list(DeviceIDs) ->
    % In our pg db, device_ids are last_xscdevid.
    case pq(Conn, "del_regs_by_device_ids", [DeviceIDs]) of
        {ok, _N} ->
            ok;
        Err ->
            Err
    end.

%%--------------------------------------------------------------------
%% @doc Delete push registrations by internal registration id.
%% @end
%%--------------------------------------------------------------------
-spec delete_push_regs_by_ids(Ctx, IDs) -> Result when
      Ctx :: ctx(), IDs :: reg_id_keys(),
      Result :: ok | {error, term()}.
delete_push_regs_by_ids(#?CTX{conn=Conn, prep_qs=QMap}, IDs) ->
    Stmt = maps:get("del_reg_by_id", QMap),
    Batch = [{Stmt, [DeviceID, Tag]} || {DeviceID, Tag} <- IDs],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by service-token.
%% @end
%%--------------------------------------------------------------------
-spec delete_push_regs_by_svc_toks(Ctx, SvcToks) -> Result when
      Ctx :: ctx(), SvcToks :: [svc_tok_key()],
      Result :: ok | {error, term()}.
delete_push_regs_by_svc_toks(#?CTX{conn=Conn,
                                   prep_qs=QMap},
                             SvcToks) when is_list(SvcToks) ->
    Stmt = maps:get("del_reg_by_svc_tok", QMap),
    Batch = [{Stmt, [svc_to_type(Svc), Tok]} || {Svc, Tok} <- SvcToks],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by tags.
%% @end
%%--------------------------------------------------------------------
-spec delete_push_regs_by_tags(Ctx, Tags) -> Result when
      Ctx :: ctx(), Tags :: [binary()], Result :: ok | {error, term()}.
delete_push_regs_by_tags(#?CTX{conn=Conn,
                               prep_qs=QMap}, Tags) when is_list(Tags) ->
    Stmt = maps:get("del_reg_by_tag", QMap),
    Batch = [{Stmt, [Tag]} || Tag <- Tags],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Update one or more push registration's last invalid timestamp, given a
%% list of `{{Service, Token}, Timestamp}'.
%% @end
%%--------------------------------------------------------------------
-spec update_invalid_timestamps_by_svc_toks(Ctx, SvcToksTs) -> Result when
      Ctx :: ctx(), SvcToksTs :: mult_svc_tok_ts(),
      Result :: ok | {error, term()}.
update_invalid_timestamps_by_svc_toks(#?CTX{conn=Conn,
                                            prep_qs=QMap},
                                      SvcToksTs) when is_list(SvcToksTs) ->
    Stmt = maps:get("update_invalid_ts_svc_tok", QMap),
    Batch = [{Stmt, [posix_ms_to_pg_datetime(TS), svc_to_type(Svc), Tok]}
             || {{Svc, Tok}, TS} <- SvcToksTs],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Get registration information by device id.
%%
%% Return a list of registration property lists. or `notfound'.
%% @end
%%--------------------------------------------------------------------
-spec get_registration_info_by_device_id(Ctx, DeviceID) -> Result when
      Ctx :: ctx(), DeviceID :: binary(),
      Result :: sc_push_reg_db:db_props_lookup_result().
get_registration_info_by_device_id(#?CTX{conn=Conn}, DeviceID) ->
    get_registration_info_impl(Conn, DeviceID, fun lookup_reg_device_id/2).

%%--------------------------------------------------------------------
%% @doc Get registration information by unique id.
%% @see sc_push_reg_db:make_id/2
%% @end
%%--------------------------------------------------------------------
-spec get_registration_info_by_id(Ctx, ID) -> Result when
      Ctx :: ctx(), ID :: reg_id_key(),
      Result :: sc_push_reg_db:db_props_lookup_result().
get_registration_info_by_id(#?CTX{conn=Conn}, ID) ->
    get_registration_info_impl(Conn, ID, fun lookup_reg_id/2).

%%--------------------------------------------------------------------
%% @doc Get registration information by service-token.
%% @see sc_push_reg_api:make_svc_tok/2
%% @end
%%--------------------------------------------------------------------
-spec get_registration_info_by_svc_tok(Ctx, SvcTok) -> Result when
      Ctx :: ctx(), SvcTok :: svc_tok_key(),
      Result :: sc_push_reg_db:db_props_lookup_result().
get_registration_info_by_svc_tok(#?CTX{conn=Conn},
                                 {_Service, _Token} = SvcTok) ->
    get_registration_info_impl(Conn, SvcTok, fun lookup_svc_tok/2).

%%--------------------------------------------------------------------
%% @doc Get registration information by tag.
%% @end
%%--------------------------------------------------------------------
-spec get_registration_info_by_tag(Ctx, Tag) -> Result when
      Ctx :: ctx(), Tag :: binary(),
      Result :: sc_push_reg_db:db_props_lookup_result().
get_registration_info_by_tag(#?CTX{conn=Conn}, Tag) ->
    get_registration_info_impl(Conn, Tag, fun lookup_reg_tag/2).

%%--------------------------------------------------------------------
%% @doc Return `true' if push registration proplist is valid.
%% @end
%%--------------------------------------------------------------------
-spec is_valid_push_reg(Ctx, PL) -> boolean() when
      Ctx :: ctx(), PL :: reg_proplist().
is_valid_push_reg(#?CTX{}, PL) ->
    try make_upsert_params(PL) of
        _ -> true
    catch _:_ -> false
    end.

%%--------------------------------------------------------------------
%% @doc Save a list of push registrations.
%% @end
%%--------------------------------------------------------------------
-spec save_push_regs(Ctx, NonemptyRegProplists) -> Result when
      Ctx :: ctx(), NonemptyRegProplists :: nonempty_reg_proplists(),
      Result :: ok | {error, term()}.
save_push_regs(#?CTX{conn=Conn, prep_qs=QMap}, [_|_]=NonemptyRegProplists) ->
    %% DEBUG
    lager:debug("[~p:~p] Called save_push_regs", [?ROLE, self()]),
    Stmt = maps:get("call_upsert_func", QMap),
    Batch = [{Stmt, make_upsert_params(PL)} || PL <- NonemptyRegProplists],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Re-register invalidated tokens.
%% @end
%%--------------------------------------------------------------------
-spec reregister_ids(Ctx, IDToks) -> ok when
      Ctx :: ctx(), IDToks :: [{RegID, NewToken}],
      RegID :: reg_id_key(), NewToken :: binary().
reregister_ids(#?CTX{conn=Conn, prep_qs=QMap}, IDToks) when is_list(IDToks) ->
    Stmt = maps:get("reregister_id", QMap),
    Batch = [{Stmt, [NewTok, DevId, Tag]}
             || {{DevId, Tag}, NewTok} <- IDToks],
    do_batch(Conn, Batch).

%%--------------------------------------------------------------------
%% @doc Re-register invalidated tokens by service and token.
%% @end
%%--------------------------------------------------------------------
-spec reregister_svc_toks(Ctx, SvcToks) -> ok when
      Ctx :: ctx(), SvcToks :: [{SvcTok, NewToken}],
      SvcTok :: svc_tok_key(), NewToken :: binary().
reregister_svc_toks(#?CTX{conn=Conn,
                          prep_qs=QMap}, SvcToks) when is_list(SvcToks) ->
    Stmt = maps:get("reregister_svc_tok", QMap),
    Batch = [{Stmt, [NewTok, svc_to_type(Svc), Tok]}
             || {{Svc, Tok}, NewTok} <- SvcToks],
    do_batch(Conn, Batch).

%%====================================================================
%% Internal functions
%%====================================================================

%%--------------------------------------------------------------------
make_context(Conn, Config) ->
    try
        %% Create temp table to ensure there exists a pg_temp schema.
        ok = ensure_temp_schema(Conn),
        ok = create_local_functions(Conn, ?DB_PUSH_TOKENS_TBL),
        PTQueries = push_tokens_queries(?DB_PUSH_TOKENS_TBL),
        {ok, PrepQs} = prepare_statements(Conn, PTQueries),
        {ok, #?CTX{conn=Conn,
                   config=Config,
                   prep_qs=PrepQs}}
    catch
        _:Error ->
            (catch epgsql:close(Conn)),
            Error
    end.

%%--------------------------------------------------------------------
-spec prepare_statements(Conn, Queries) -> Result when
      Conn :: conn(), Queries :: [{StmtName, QueryIoList}],
      StmtName :: query_name(), QueryIoList :: iolist(),
      Result :: {ok, PrepQs} | {error, Reason},
      PrepQs :: map(), Reason :: [any()].
prepare_statements(Conn, Queries) ->
    PrepQs = prepared_queries(Conn, Queries),
    {ok, maps:from_list([{S#statement.name, S} || S <- PrepQs])}.

%%--------------------------------------------------------------------
ensure_temp_schema(Conn) ->
    Query = "create temp table if not exists temp_junk_(x integer);",
    {ok, [], []} = epgsql:with_transaction(Conn,
                                           fun(C) ->
                                                   epgsql:squery(C, Query)
                                           end),
    ok.

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
%% @private
%% For debugging only - if called on large db, unhappy days ahead.
-spec db_all_regs(Conn) -> ListOfRegs when
      Conn:: conn(),
      ListOfRegs :: sc_push_reg_db:mult_reg_db_props().
db_all_regs(Conn) ->
    do_reg_pquery(Conn, "all_regs", []).

%%--------------------------------------------------------------------
%% @private
-spec lookup_reg_id(conn(), reg_id_key()) -> push_reg_list().
lookup_reg_id(Conn, {DevID, Tag}) ->
    do_reg_pquery(Conn, "lookup_reg_id", [DevID, Tag]).

%%--------------------------------------------------------------------
%% @private
-spec lookup_reg_device_id(conn(), binary()) -> push_reg_list().
lookup_reg_device_id(Conn, DevID) when is_binary(DevID) ->
    do_reg_pquery(Conn, "lookup_reg_device_id", [DevID]).

%%--------------------------------------------------------------------
%% @private
-spec lookup_reg_tag(conn(), binary()) -> push_reg_list().
lookup_reg_tag(Conn, Tag) when is_binary(Tag) ->
    do_reg_pquery(Conn, "lookup_reg_tag", [Tag]).

%%--------------------------------------------------------------------
%% @private
-spec lookup_svc_tok(conn(), svc_tok_key()) -> push_reg_list().
lookup_svc_tok(Conn, {Svc, Tok}) when is_atom(Svc), is_binary(Tok) ->
    do_reg_pquery(Conn, "lookup_reg_svc_tok", [svc_to_type(Svc), Tok]).

%%--------------------------------------------------------------------
get_registration_info_impl(Conn, Key, Lookup) when is_function(Lookup, 2) ->
    case Lookup(Conn, Key) of
        [_|_] = Regs ->
            Regs;
        [] ->
            notfound
    end.

%%--------------------------------------------------------------------
-spec do_reg_pquery(Conn, QueryName, Args) -> Result when
      Conn :: conn(), QueryName :: query_name(), Args :: [bind_param()],
      Result :: [proplists:proplist()] | scpf_error().
do_reg_pquery(Conn, QueryName, Args) ->
    case pq(Conn, QueryName, Args) of
        {ok, Count} when is_integer(Count) ->
            [];
        {ok, Maps} when is_list(Maps) ->
            push_reg_maps_to_props(Maps);
        {ok, _Count, Maps} ->
            push_reg_maps_to_props(Maps);
        {error, _}=Error ->
            Error
    end.

%%--------------------------------------------------------------------
-spec push_reg_maps_to_props(Maps) -> ListOfProplists when
      Maps :: [map()], ListOfProplists  :: [proplists:proplist()].
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
%% @private
%% @doc Run a prepared query
-spec pq(Conn, QueryName, Args) -> Reply when
      Conn :: conn(), QueryName :: query_name(), Args :: [bind_param()],
      Reply :: {ok, Count}
             | {ok, Columns, Rows}
             | {ok, QueryMaps}
             | {error, Reason},
      Count :: integer(),
      Columns :: cols(), Rows :: rows(),
      QueryMaps :: [map()], Reason :: scpf_error().
pq(Conn, QueryName, Args) ->
    case epq(Conn, QueryName, Args) of
        {ok, Count} when is_integer(Count) ->
            {ok, Count};
        {ok, Columns, Rows} ->
            {ok, pg2scpf_maps(Columns, Rows)};
        {ok, Count, Columns, Rows} ->
            {ok, Count, pg2scpf_maps(Columns, Rows)};
        {error, #error{}=E} ->
            {error, pg2scpf_err(E)};
        {rollback, Err}=E ->
            lager:error("Transaction rollback: ~p", [Err]),
            {error, pg2scpf_err(E)}
    end.

%%--------------------------------------------------------------------
-compile({inline, [{epq, 3}]}).
%% @private
%% @equiv epgsql:prepared_query(C, Q, Args)
-spec epq(C, Q, Args) -> Reply when
      C :: conn(), Q :: string(), Args :: [bind_param()],
      Reply :: any() | {rollback, any()}.
epq(C, Q, Args) ->
    Txn = fun(Conn) -> epgsql:prepared_query(Conn, Q, Args) end,
    epgsql:with_transaction(C, Txn).

%%--------------------------------------------------------------------
-spec do_batch(Conn, Batch) -> Result when
      Conn :: conn(), Batch :: [{stmt(), [bind_param()]}],
      Result :: ok | {error, term()}.
do_batch(Conn, Batch) ->
    Pid = self(),
    {ok, [], []} = epgsql:squery(Conn, "BEGIN"),
    lager:debug("[~p:~p] Ok: do_batch ~s", [?ROLE, Pid, "BEGIN"]),
    try lists:partition(fun(T) ->
                                element(1, T) =:= ok
                        end, epgsql:execute_batch(Conn, Batch)) of
        {_, []} -> % All good
            {ok, [], []} = epgsql:squery(Conn, "COMMIT"),
            lager:debug("[~p:~p] Ok: do_batch ~s", [?ROLE, Pid, "COMMIT"]),
            ok;
        {_, Errs} ->
            {ok, [], []} = epgsql:squery(Conn, "ROLLBACK"),
            lager:debug("[~p:~p] Ok: do_batch ~s", [?ROLE, Pid, "ROLLBACK"]),
            {error, Errs}
    catch
        _:Err ->
            {ok, [], []} = epgsql:squery(Conn, "ROLLBACK"),
            lager:debug("[~p:~p] Ok: do_batch ~s", [?ROLE, Pid, "ROLLBACK"]),
            {error, Err}
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
      Columns :: cols(), Rows :: rows(), Result :: [map()].
pg2scpf_maps(Columns, Rows) when is_list(Rows) ->
    NumberedCols = lists:zip(Columns, lists:seq(1, length(Columns))),
    [pg2scpf(NumberedCols, Row) || Row <- Rows].


%%--------------------------------------------------------------------
-spec pg2scpf_err(Error) -> ScpfError when
      Error :: pg_error() | other_error(), ScpfError :: scpf_error().
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
-spec pg2scpf(NumberedCols, Row) -> Map when
      NumberedCols :: [{Col, ColNo}], Row :: row(),
      Col :: col(), ColNo :: pos_integer(),
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
    {Secs, Micros} = float_secs_to_int(FracSecs),
    POSIXSecs = datetime_to_posix_secs({Date,{H,M,Secs}}),
    {POSIXSecs div 1000000, POSIXSecs rem 1000000, Micros}.

%%--------------------------------------------------------------------
-spec posix_ms_to_pg_datetime(PosixMs) -> PgDateTime when
      PosixMs :: non_neg_integer(), PgDateTime :: epgsql:pg_datetime().
posix_ms_to_pg_datetime(PosixMs) ->
    {_,_,Micros} = TS = sc_push_reg_db:from_posix_time_ms(PosixMs),
    {Date, {H,M,S}} = calendar:now_to_universal_time(TS),
    {Date, {H, M, (S * 1000000 + Micros) / 1000000.0}}.

%%--------------------------------------------------------------------
-compile({inline, [{datetime_to_posix_secs, 1}]}).
datetime_to_posix_secs({{_,_,_},{_,_,_}}=DT) ->
    calendar:datetime_to_gregorian_seconds(DT) - ?EPOCH_GREGORIAN_SECONDS.

%%--------------------------------------------------------------------
-compile({inline, [{float_secs_to_int, 1}]}).
-spec float_secs_to_int(Secs) -> {IntSecs, IntMicros} when
      Secs :: float() | non_neg_integer(),
      IntSecs :: non_neg_integer(), IntMicros :: non_neg_integer().
float_secs_to_int(Secs) when is_float(Secs) ->
    {erlang:trunc(Secs), erlang:round(Secs * 1000000.0) rem 1000000};
float_secs_to_int(Secs) when is_integer(Secs) ->
    {Secs, 0}.

%%--------------------------------------------------------------------
-spec prepared_queries(Conn, Queries) -> Stmts when
      Conn :: epgsql:connection(), Queries :: [{StmtName, QueryIoList}],
      StmtName :: query_name(), QueryIoList :: iolist(), Stmts :: [stmt()].
prepared_queries(Conn, Queries) ->
    Txn = fun(C) ->
                  lists:foldl(fun({QName, Q}, Acc) ->
                                      [parse(C, QName, Q) | Acc]
                              end, [], Queries)
          end,
    case epgsql:with_transaction(Conn, Txn) of
        {rollback, _}=Err ->
            erlang:error(pg2scpf_err(Err));
        Stmts ->
            lager:debug("Queries parsed successfully: ~B", [length(Stmts)]),
            Stmts
    end.

%%--------------------------------------------------------------------
-spec parse(Conn, QueryName, Query) -> Stmt when
      Conn :: conn(), QueryName :: query_name(), Query :: iolist(),
      Stmt :: stmt().
parse(Conn, QueryName, Query) ->
    case epgsql:parse(Conn, QueryName, Query, []) of
        {ok, Stmt} ->
            lager:debug("SUCCESS, prepared query ~s: [~s]",
                        [QueryName, list_to_binary(Query)]),
            Stmt;
        {error, Err} ->
            lager:error("Error (~p) preparing query ~s: [~s]",
                        [Err, QueryName, list_to_binary(Query)]),
            erlang:error(Err)
    end.

%%--------------------------------------------------------------------
-spec push_tokens_queries(Tab) -> Queries when
      Tab :: iolist(), Queries :: [{Name, Query}],
      Name :: string(), Query :: iolist().
push_tokens_queries(Tab) ->
    Tbl = sc_util:to_bin(Tab),
    Cols = push_tokens_colnames_iolist(),
    [{"lookup_one_reg",
      [<<"select id from ">>, Tbl,
       <<" where uuid = $1 and type = $2 and token = $3 and appname = $4">>,
       <<" limit 1">>]},
     {"all_regs", make_select_all_query(Tbl, Cols)},
     {"lookup_reg_id",
      make_lookup_query(Tbl, Cols, <<"last_xscdevid = $1 and uuid = $2">>)},
     {"lookup_reg_device_id",
      make_lookup_query(Tbl, Cols, <<"last_xscdevid = $1">>)},
     {"lookup_reg_tag",
      make_lookup_query(Tbl, Cols, <<"uuid = $1">>)},
     {"lookup_reg_svc_tok",
      make_lookup_query(Tbl, Cols, <<"type = $1 and token = $2">>)},
     {"del_regs_by_device_ids",
      make_delete_query(Tbl, <<"last_xscdevid = any($1)">>)},
     {"del_reg_by_id",
      make_delete_query(Tbl, <<"last_xscdevid = $1 and uuid = $2">>)},
     {"del_reg_by_svc_tok",
      make_delete_query(Tbl, <<"type = $1 and token = $2">>)},
     {"del_reg_by_tag", make_delete_query(Tbl, <<"uuid = $1">>)},
     {"update_invalid_ts_svc_tok",
      [<<"update ">>, Tbl, <<" set last_invalid_on = $1">>,
       $\s, <<"where type = $2 and token = $3">>]},
     {"reregister_id",
      [<<"update ">>, Tbl, <<" set token = $1">>,
       <<" where last_xscdevid = $2 and uuid = $3">>]},
     {"reregister_svc_tok",
      [<<"update ">>, Tbl, <<" set token = $1">>,
       <<" where type = $2 and token = $3">>]},
     {"insert_reg",
      [<<"insert into ">>, Tbl,
       <<" (uuid, type, token, appname, last_xscdevid) ">>,
       <<" values ($1, $2, $3, $4, $5)">>]},
     {"update_reg",
      [<<"update ">>, Tbl,
       <<" set uuid = $1, type = $2, token = $3,">>,
       <<" appname = $4, last_xscdevid = $5, last_seen_on = now() at time zone 'utc' ">>,
       <<" where id = $6">>]},
     {"call_upsert_func", make_call_upsert_function()}
    ].

%%--------------------------------------------------------------------
create_local_functions(Conn, Tbl) ->
     Q = make_upsert_function_query(Tbl),
     {ok, [], []} = epgsql:with_transaction(Conn, fun(C) ->
                                                          epgsql:squery(C, Q)
                                                  end),
     lager:debug("Created upsert function: ~s", [sc_util:to_bin(Q)]),
     ok.

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
-spec push_tokens_colnames_iolist() -> iolist().
push_tokens_colnames_iolist() ->
    bjoin(push_tokens_colnames(), <<",">>).

%%--------------------------------------------------------------------
-spec bjoin(ListOfBinaries, Sep) -> JoinedList when
      ListOfBinaries :: [binary()], Sep :: binary(),
      JoinedList :: [binary()].
bjoin(ListOfBinaries, <<Sep/binary>>) ->
    bjoin(ListOfBinaries, Sep, []).

%%--------------------------------------------------------------------
-spec bjoin(ListOfBinaries, Sep, Acc) -> JoinedList when
      ListOfBinaries :: [binary()], Sep :: binary(), Acc :: list(),
      JoinedList :: [binary()].
bjoin([<<B/binary>>], <<Sep/binary>>, Acc) ->
    bjoin([], Sep, [B | Acc]);
bjoin([<<B/binary>> | Rest], <<Sep/binary>>, Acc) ->
    bjoin(Rest, Sep, [Sep, B | Acc]);
bjoin([], <<_Sep/binary>>, Acc) ->
    lists:reverse(Acc).

%%--------------------------------------------------------------------
-spec make_select_all_query(Tbl, Cols) -> Query when
      Tbl :: binary(), Cols :: [binary()], Query :: iolist().
make_select_all_query(Tbl, Cols) ->
    [<<"select ">>, Cols, <<" from ">>, Tbl].

%%--------------------------------------------------------------------
-spec make_lookup_query(Tbl, Cols, WhereCondition) -> Query when
      Tbl :: binary(), Cols :: [binary()],
      WhereCondition :: binary(), Query :: iolist().
make_lookup_query(Tbl, Cols, WhereCondition) ->
    [<<"select ">>, Cols, <<" from ">>, Tbl,
     <<" where ">>, WhereCondition].

%%--------------------------------------------------------------------
-spec make_delete_query(Tbl, WhereCondition) -> Query when
      Tbl :: binary(), WhereCondition :: binary(), Query :: iolist().
make_delete_query(Tbl, WhereCondition) ->
    [<<"delete from ">>, Tbl, <<" where ">>, WhereCondition].

%%--------------------------------------------------------------------
%% @private
%% @doc We're using the pg_temp namespace here so that the stored procedure is
%% not persisted, which otherwise causes a "tuple concurrently updated" error.
-spec make_upsert_function_query(Tbl) -> Query when
      Tbl :: binary(), Query :: iolist().
make_upsert_function_query(Tbl) ->
    [<<"create or replace function pg_temp.push_tokens_upsert">>,
     <<"(uuid_ text, type_ text, token_ text, appname_ text, xscdevid_ text)
            returns integer
            language plpgsql
            strict
       as $function$
          declare
            r record;
          begin
            select a.id,
                a.last_seen_on < (now() at time zone 'utc') - (interval '1 day') as needs_atime,
                a.last_xscdevid is null or a.last_xscdevid <> xscdevid_ as needs_xscdevid
                into r
              from ">>, Tbl, <<" a
              where a.uuid = uuid_
                and a.type = type_
                and a.token = token_
                and a.appname = appname_
              limit 1;
            if not found then
              insert into ">>, Tbl, <<" (uuid,type,token,appname,last_xscdevid)
                values (uuid_,type_,token_,appname_,xscdevid_);
              return 1;
            else
              if r.needs_atime or r.needs_xscdevid then
                update ">>, Tbl, <<" set last_seen_on = now() at time zone 'utc'
                  where id = r.id;
                if r.needs_xscdevid then
                  update ">>, Tbl, <<
                  " set last_xscdevid = xscdevid_
                    where id = r.id;
                  return 3;
                end if;
                return 2;
              end if;
            end if;
            return 0;
          end;
       $function$;">>].

%%--------------------------------------------------------------------
-spec make_call_upsert_function() -> Query when
      Query :: iolist().
make_call_upsert_function() ->
    [<<"select pg_temp.push_tokens_upsert">>,
     <<"($1::text, $2::text, $3::text, $4::text, $5::text)">>].

%%--------------------------------------------------------------------
-spec schema_prefix() -> binary().
schema_prefix() ->
    list_to_binary(?DB_SCHEMA_PREFIX).


%%--------------------------------------------------------------------
check_error({error, _}=E) ->
    lager:error("~p", [translate_error(E)]),
    erlang:error(E);
check_error(E) when is_tuple(E) andalso
                    tuple_size(E) >= 1 andalso
                    element(1, E) =:= ok ->
    E.

%%--------------------------------------------------------------------
translate_error({error, #error{}=E}) ->
    {db_error, pg_errstr(E)};
translate_error({error, {unsupported_auth_method, Method}}) -> % required auth method is unsupported
    {db_unsupported_auth_method, Method};
translate_error({error, timeout}) -> % request timed out
    db_timeout;
translate_error({error, closed})  -> % connection was closed
    db_closed;
translate_error({error, sync_required}) -> % error occured and epgsql:sync must be called
    db_sync_required;
translate_error(Other) ->
    Other.

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

pg_errstr(#error{}=E) ->
    lists:flatten(
      io_lib:format("postgres[~p] ~p[~s]: ~s",
                    [E#error.severity, E#error.codename, E#error.code,
                     E#error.message])).

connect(Config) ->
    Pid = self(),
    lager:info("[~p:~p] Initializing", [?ROLE, Pid]),
    case epgsql:connect(Config) of
        {ok, Conn} ->
            DB = proplists:get_value(database, Config, ""),
            lager:info("[~p:~p] Connected to database ~s", [?ROLE, Pid, DB]),
            make_context(Conn, Config);
        Error ->
            lager:warning("[~p:~p] connect error: ~p", [?ROLE, Pid, Error]),
            connect_error(Error)
    end.

connect_error(#error{}=E) ->
    translate_error({error, E});
connect_error({unsupported_auth_method, _}=Reason) ->
    {error, Reason};
connect_error(invalid_authorization_specification=Reason) ->
    {error, Reason};
connect_error(invalid_password=Reason) ->
    {error, Reason};
connect_error(UnknownError) ->
    {error, UnknownError}.
