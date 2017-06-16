%%% ==========================================================================
%%% Copyright 2015 Silent Circle
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

%%% ==========================================================================
%%% @doc
%%% This module defines the callback interface for all database-specific
%%% backends such as `sc_push_reg_db_postgres'.
%%%
%%% This is an active module that supports connection pooling.
%%% @see sc_push_reg_db_mnesia
%%% @see sc_push_reg_db_postgres
%%% @end
%%% ==========================================================================

-module(sc_push_reg_db).

-behavior(poolboy_worker).
-behavior(gen_server).

%% Out of process API calls
-export([
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

% In-process API
-export([
         make_sc_push_props/7,
         make_sc_push_props/8,
         make_sc_push_props/9,
         from_posix_time_ms/1
        ]).

%% poolboy callback and debug start function
-export([start_link/1]).

%% debug start and stop functions
-export([start/1, stop/1]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(DEFAULT_DB_MOD, sc_push_reg_db_mnesia).

-type terminate_reason() :: normal |
                            shutdown |
                            {shutdown, term()} |
                            term().

-type name() :: atom().
-type global_name() :: term().
-type via_name() :: term().
-type server_ref() :: name()
                    | {name(), node()}
                    | {global, global_name()}
                    | {via, module(), via_name()}
                    | pid().

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-type reg_id_key() :: {binary(), binary()}.
-type svc_tok_key() :: {atom(), binary()}.
-type atom_or_str() :: atom() | string().
-type atomable() :: atom() | string() | binary().
-type binable() :: atom() | binary() | integer() | iolist().
-type reg_id_keys() :: [reg_id_key()].
-type push_reg_list() :: list().
-type reg_db_props() :: [{'app_id', binary()} |
                         {'dist', binary()} |
                         {'service', atom()} |
                         {'device_id', binary()} |
                         {'tag', binary()} |
                         {'modified', tuple()} |
                         {'last_invalid_on', undefined | tuple()} |
                         {'token', binary()}].


-export_type([
              reg_id_key/0,
              svc_tok_key/0,
              atom_or_str/0,
              atomable/0,
              binable/0,
              reg_id_keys/0,
              reg_db_props/0,
              push_reg_list/0
             ]).

-define(S, ?MODULE).

-type ctx() :: term().

-record(?S, {db_mod :: atom(),
             db_config,
             db_ctx :: ctx()}).

-type state() :: #?S{}.

%%--------------------------------------------------------------------
%% Behavior callbacks
%%--------------------------------------------------------------------
-callback db_init(Config) -> {ok, Context} | {error, Reason}
    when Config :: term(), Context :: ctx(), Reason :: term().


-callback db_info(ctx()) -> Info
    when Info :: proplists:proplist().


-callback db_terminate(Context) -> ok when
      Context :: ctx().


-callback all_reg(term()) -> list().


-callback all_registration_info(ctx()) -> Result
    when Result :: [sc_types:reg_proplist()].


-callback check_id(ctx(), RegIdKey) -> Result
    when RegIdKey :: reg_id_key(), Result :: reg_id_key().


-callback check_ids(ctx(), RegIdKeys) -> Result
    when RegIdKeys :: reg_id_keys(), Result :: reg_id_keys().


-callback create_tables(ctx(), Config) -> any()
    when Config :: any().


-callback delete_push_regs_by_device_ids(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback delete_push_regs_by_ids(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback delete_push_regs_by_svc_toks(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback update_invalid_timestamps_by_svc_toks(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback delete_push_regs_by_tags(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback get_registration_info_by_device_id(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback get_registration_info_by_id(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback get_registration_info_by_svc_tok(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback get_registration_info_by_tag(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback is_valid_push_reg(ctx(), Key) -> Result
    when Key :: term(), Result :: term().


-callback reregister_ids(ctx(), Ids) -> ok
    when Ids :: [{reg_id_key(), binary()}].


-callback reregister_svc_toks(ctx(), SvcToks) -> ok
    when SvcToks :: [{svc_tok_key(), binary()}].


-callback save_push_regs(ctx(), ListOfProplists) -> Result
    when ListOfProplists :: [sc_types:reg_proplist(), ...],
         Result :: ok | {error, term()}.

%%====================================================================
%% API
%%====================================================================
%%--------------------------------------------------------------------
%% @doc
%% Start the server
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link(Args) -> Result when
      Args :: proplists:proplist(),
      Result :: {ok, Pid} | {error, {already_started, Pid}} | {error, Reason},
      Pid :: pid(),
      Reason :: term().
start_link(Args) ->
    gen_server:start_link(?MODULE, Args, []).

%%--------------------------------------------------------------------
%% @doc
%% Start the server without linking (for debugging and testing).
%%
%% @end
%%--------------------------------------------------------------------
-spec start(Args) -> Result when
      Args :: term(), Result :: {ok, pid()} | ignore | {error, term()}.
start(Args) ->
    gen_server:start(?MODULE, Args, []).

%%--------------------------------------------------------------------
%% @doc
%% Stop an unlinked server (for testing and debugging).
%%
%% @end
%%--------------------------------------------------------------------
-spec stop(ServerRef) -> ok when ServerRef :: server_ref().
stop(ServerRef) ->
    gen_server:stop(ServerRef).

%%--------------------------------------------------------------------
%% @private
%% @deprecated For debug only
%% @doc Return a list of property lists of all registrations.
%% @end
%%--------------------------------------------------------------------
-spec all_registration_info(pid()) -> [sc_types:reg_proplist()].
all_registration_info(Worker) ->
    gen_server:call(Worker, all_registration_info).

%%--------------------------------------------------------------------
%% @private
%% @deprecated For debug only.
%% @doc Return a list of all push registration records.
%% @end
%%--------------------------------------------------------------------
-spec all_reg(pid()) -> push_reg_list().
all_reg(Worker) ->
    gen_server:call(Worker, all_reg).

%%--------------------------------------------------------------------
%% @doc Check registration id key.
-spec check_id(pid(), reg_id_key()) -> reg_id_key().
check_id(Worker, ID) ->
    gen_server:call(Worker, {check_id, ID}).

%%--------------------------------------------------------------------
%% @doc Check multiple registration id keys.
-spec check_ids(pid(), reg_id_keys()) -> reg_id_keys().
check_ids(Worker, IDs) ->
    gen_server:call(Worker, {check_ids, IDs}).

%%--------------------------------------------------------------------
%% @doc Create tables. May be a no-op for certain backends.
create_tables(Worker, Config) ->
    gen_server:call(Worker, {create_tables, Config}).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by device ids
-spec delete_push_regs_by_device_ids(pid(), [binary()]) -> ok |
                                                           {error, term()}.
delete_push_regs_by_device_ids(Worker, DeviceIDs) ->
    gen_server:call(Worker, {delete_push_regs_by_device_ids, DeviceIDs}).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by internal registration id.
-spec delete_push_regs_by_ids(pid(), reg_id_keys()) -> ok | {error, term()}.
delete_push_regs_by_ids(Worker, IDs) ->
    gen_server:call(Worker, {delete_push_regs_by_ids, IDs}).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by service-token.
-spec delete_push_regs_by_svc_toks(pid(), [svc_tok_key()]) -> ok | {error, term()}.
delete_push_regs_by_svc_toks(Worker, SvcToks) ->
    gen_server:call(Worker, {delete_push_regs_by_svc_toks, SvcToks}).

%%--------------------------------------------------------------------
%% @doc Update push registration invalid timestamp by service-token.
-spec update_invalid_timestamps_by_svc_toks(Worker, SvcToksTs) -> ok | {error, term()} when
      Worker :: pid(), SvcToksTs :: [{svc_tok_key(), non_neg_integer()}].
update_invalid_timestamps_by_svc_toks(Worker, SvcToksTs) ->
    gen_server:call(Worker, {update_invalid_timestamps_by_svc_toks, SvcToksTs}).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by tags.
-spec delete_push_regs_by_tags(pid(), [binary()]) -> ok | {error, term()}.
delete_push_regs_by_tags(Worker, Tags) ->
    gen_server:call(Worker, {delete_push_regs_by_tags, Tags}).

%%--------------------------------------------------------------------
%% @doc Get registration information by device id.
-spec get_registration_info_by_device_id(pid(), binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_device_id(Worker, DeviceID) ->
    gen_server:call(Worker, {get_registration_info_by_device_id, DeviceID}).

%%--------------------------------------------------------------------
%% @doc Get registration information by unique id.
%% @see:sc_push_reg_api: make_id/2
-spec get_registration_info_by_id(pid(), reg_id_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_id(Worker, ID) ->
    gen_server:call(Worker, {get_registration_info_by_id, ID}).

%%--------------------------------------------------------------------
%% @doc Get registration information by service-token.
%% @see sc_push_reg_api:make_svc_tok/2
-spec get_registration_info_by_svc_tok(pid(), svc_tok_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_svc_tok(Worker, SvcTok) ->
    gen_server:call(Worker, {get_registration_info_by_svc_tok, SvcTok}).

%%--------------------------------------------------------------------
%% @doc Get registration information by tag.
-spec get_registration_info_by_tag(pid(), binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(Worker, Tag) ->
    gen_server:call(Worker, {get_registration_info_by_tag, Tag}).

%%--------------------------------------------------------------------
%% @doc Is push registration proplist valid?
-spec is_valid_push_reg(pid(), sc_types:proplist(atom(), term())) -> boolean().
is_valid_push_reg(Worker, PL) ->
    gen_server:call(Worker, {is_valid_push_reg, PL}).

%%--------------------------------------------------------------------
%% @doc Save a list of push registrations.
-spec save_push_regs(Worker, ListOfPropLists) -> ok | {error, term()} when
      Worker :: pid(), ListOfPropLists :: [sc_types:reg_proplist(), ...].
save_push_regs(Worker, ListOfProplists) ->
    gen_server:call(Worker, {save_push_regs, ListOfProplists}).

%%--------------------------------------------------------------------
%% @doc Re-register invalidated tokens
-spec reregister_ids(pid(), [{reg_id_key(), binary()}]) -> ok.
reregister_ids(Worker, IDToks) ->
    gen_server:call(Worker, {reregister_ids, IDToks}).

%%--------------------------------------------------------------------
%% @doc Re-register invalidated tokens by svc_tok
-spec reregister_svc_toks(pid(), [{svc_tok_key(), binary()}]) -> ok.
reregister_svc_toks(Worker, SvcToks) ->
    gen_server:call(Worker, {reregister_svc_toks, SvcToks}).

%%--------------------------------------------------------------------
%% Locally-implemented APIs
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @doc Create a property list from push registration data.
-spec make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                         LastModifiedOn) -> Result
    when
      Service :: atomable(), Token :: binable(), DeviceId :: binable(),
      Tag :: binable(), AppId :: binable(), Dist :: binable(),
      LastModifiedOn :: erlang:timestamp(), Result :: reg_db_props()
      .
make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                   {_,_,_}=LastModifiedOn) ->
    LastInvalidOn = undefined,
    make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                       LastModifiedOn, LastInvalidOn).

%%--------------------------------------------------------------------
%% @doc Create a property list from push registration data.
-spec make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                         LastModifiedOn, LastInvalidOn) -> Result
    when
      Service :: atomable(), Token :: binable(), DeviceId :: binable(),
      Tag :: binable(), AppId :: binable(), Dist :: binable(),
      LastModifiedOn :: erlang:timestamp(),
      LastInvalidOn :: undefined | erlang:timestamp(),
      Result :: reg_db_props()
      .
make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                   {_,_,_}=LastModifiedOn, LastInvalidOn) ->
    CreatedOn = erlang:timestamp(),
    make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                       LastModifiedOn, LastInvalidOn, CreatedOn).

%%--------------------------------------------------------------------
%% @doc Create a property list from push registration data.
-spec make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                         LastModifiedOn, LastInvalidOn, CreatedOn) -> Result
    when
      Service :: atomable(), Token :: binable(), DeviceId :: binable(),
      Tag :: binable(), AppId :: binable(), Dist :: binable(),
      LastModifiedOn :: erlang:timestamp(),
      LastInvalidOn :: undefined | erlang:timestamp(),
      CreatedOn :: erlang:timestamp(),
      Result :: reg_db_props()
      .
make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                   {_,_,_}=LastModifiedOn,
                   LastInvalidOn,
                   {_,_,_}=CreatedOn) ->
    [
        {device_id, sc_util:to_bin(DeviceId)},
        {service, sc_util:to_atom(Service)},
        {token, sc_util:to_bin(Token)},
        {tag, sc_util:to_bin(Tag)},
        {app_id, sc_util:to_bin(AppId)},
        {dist, sc_util:to_bin(Dist)},
        {created_on, CreatedOn},
        {modified, LastModifiedOn},
        {last_invalid_on, LastInvalidOn}
    ].

%%--------------------------------------------------------------------
%% @doc Convert timestamp in milliseconds from epoch to Erlang `now'
%% format.
%% @end
%%--------------------------------------------------------------------
from_posix_time_ms(TimestampMs) ->
    {TimestampMs div 1000000000,
     TimestampMs rem 1000000000 div 1000,
     TimestampMs rem 1000 * 1000}.

%%--------------------------------------------------------------------
%% gen_server callbacks
%%--------------------------------------------------------------------

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init(term()) -> {ok, State::state()} |
                      {ok, State::state(), Timeout::timeout()} |
                      {ok, State::state(), 'hibernate'} |
                      {stop, Reason::term()} |
                      'ignore'
                      .
init([_|_]=Args) ->
    erlang:process_flag(trap_exit, true),
    DbMod = sc_util:req_val(db_mod, Args),
    DbConfig = sc_util:req_val(db_config, Args),
    {ok, DbCtx} = DbMod:db_init(DbConfig),
    {ok, #?S{db_mod = DbMod,
             db_config = DbConfig,
             db_ctx = DbCtx}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request::term(),
                  From::{pid(), Tag::term()},
                  State::state()) ->
    {reply, Reply::term(), NewState::state()} |
    {reply, Reply::term(), NewState::state(), Timeout::timeout()} |
    {reply, Reply::term(), NewState::state(), 'hibernate'} |
    {noreply, NewState::state()} |
    {noreply, NewState::state(), 'hibernate'} |
    {noreply, NewState::state(), Timeout::timeout()} |
    {stop, Reason::term(), Reply::term(), NewState::state()} |
    {stop, Reason::term(), NewState::state()}
    .

handle_call(all_registration_info, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:all_registration_info(Ctx),
    {reply, Reply, St};
handle_call(all_reg, _From, #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:all_reg(Ctx),
    {reply, Reply, St};
handle_call({check_id, ID}, _From, #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:check_id(Ctx, ID),
    {reply, Reply, St};
handle_call({check_ids, IDs}, _From, #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:check_ids(Ctx, IDs),
    {reply, Reply, St};
handle_call({create_tables, Config}, _From, #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:create_tables(Ctx, Config),
    {reply, Reply, St};
handle_call({delete_push_regs_by_device_ids, DeviceIDs}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:delete_push_regs_by_device_ids(Ctx, DeviceIDs),
    {reply, Reply, St};
handle_call({delete_push_regs_by_ids, IDs}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:delete_push_regs_by_ids(Ctx, IDs),
    {reply, Reply, St};
handle_call({delete_push_regs_by_svc_toks, SvcToks}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:delete_push_regs_by_svc_toks(Ctx, SvcToks),
    {reply, Reply, St};
handle_call({delete_push_regs_by_tags, Tags}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:delete_push_regs_by_tags(Ctx, Tags),
    {reply, Reply, St};
handle_call({update_invalid_timestamps_by_svc_toks, SvcToksTs},
            _From, #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:update_invalid_timestamps_by_svc_toks(Ctx, SvcToksTs),
    {reply, Reply, St};
handle_call({get_registration_info_by_device_id, DeviceID}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:get_registration_info_by_device_id(Ctx, DeviceID),
    {reply, Reply, St};
handle_call({get_registration_info_by_id, ID}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:get_registration_info_by_id(Ctx, ID),
    {reply, Reply, St};
handle_call({get_registration_info_by_svc_tok, SvcTok}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:get_registration_info_by_svc_tok(Ctx, SvcTok),
    {reply, Reply, St};
handle_call({get_registration_info_by_tag, Tag}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:get_registration_info_by_tag(Ctx, Tag),
    {reply, Reply, St};
handle_call({save_push_regs, ListOfProplists}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:save_push_regs(Ctx, ListOfProplists),
    {reply, Reply, St};
handle_call({is_valid_push_reg, PL}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:is_valid_push_reg(Ctx, PL),
    {reply, Reply, St};
handle_call({reregister_ids, IdToks}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:reregister_ids(Ctx, IdToks),
    {reply, Reply, St};
handle_call({reregister_svc_toks, SvcToks}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:reregister_svc_toks(Ctx, SvcToks),
    {reply, Reply, St};
handle_call(_Request, _From, State) ->
    Reply = {error, invalid_request},
    {reply, Reply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling cast messages
%%
%% @spec handle_cast(Msg, State) -> {noreply, State} |
%%                                  {noreply, State, Timeout} |
%%                                  {stop, Reason, State}
%% @end
%%--------------------------------------------------------------------
-spec handle_cast(Request::term(),
                  State::state()) ->
    {noreply, NewState::state()} |
    {noreply, NewState::state(), 'hibernate'} |
    {noreply, NewState::state(), Timeout::timeout()} |
    {stop, Reason::term(), NewState::state()}
    .

handle_cast(_Msg, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling all non call/cast messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_info(Request::term(),
                  State::state()) ->
    {noreply, NewState::state()} |
    {noreply, NewState::state(), 'hibernate'} |
    {noreply, NewState::state(), Timeout::timeout()} |
    {stop, Reason::term(), NewState::state()}
    .
handle_info(_Info, State) ->
    {noreply, State}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% This function is called by a gen_server when it is about to
%% terminate. It should be the opposite of Module:init/1 and do any
%% necessary cleaning up. When it returns, the gen_server terminates
%% with Reason. The return value is ignored.
%%
%% @end
%%--------------------------------------------------------------------
-spec terminate(Reason::terminate_reason(),
                State::state()) -> no_return().
terminate(shutdown, #?S{db_mod=Mod, db_ctx=Ctx}) ->
    lager:debug("~p terminated via shutdown", [Mod]),
    (catch Mod:db_terminate(Ctx));
terminate(Reason, St) ->
    lager:warning("~p terminated for reason ~p", [St#?S.db_mod, Reason]).

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term() | {down, term()},
                  State::state(),
                  Extra::term()) ->
    {ok, NewState::state()} |
    {error, Reason::term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

