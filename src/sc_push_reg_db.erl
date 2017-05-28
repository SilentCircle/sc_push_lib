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

-define(SECS_TO_MS(Secs), (Secs * 1000)).
-define(MINS_TO_SECS(Mins), (Mins * 60)).
-define(MINS_TO_MS(Mins), ?SECS_TO_MS(?MINS_TO_SECS(Mins))).

-define(DEFAULT_DB_MOD, sc_push_reg_db_mnesia).
-define(INITIAL_DELAY, 500).
-define(MAXIMUM_DELAY, ?MINS_TO_MS(5)).
-define(TIMEOUT, ?SECS_TO_MS(5)).


%%--------------------------------------------------------------------
%% gen_server types
%%--------------------------------------------------------------------
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
%% Utility types
%%--------------------------------------------------------------------
-type atom_or_str() :: atom() | string().
-type atomable() :: atom() | string() | binary().
-type binable() :: atom() | binary() | integer() | iolist().
-type posix_timestamp_milliseconds() :: non_neg_integer().

%%--------------------------------------------------------------------
%% Registration DB types
%%--------------------------------------------------------------------
-type device_id() :: binary(). % A binary string denoting the installation and
                               % application-specific device identifier. The
                               % format and content of the string is opaque.

-type tag() :: binary().       % A binary string denoting an identifier that
                               % links together a number of device
                               % registrations. This could be an email address,
                               % a UUID, or something else. This value is
                               % totally opaque to the registration service,
                               % so if it is a string, it may be case-sensitive.
                               %
-type service() :: atom().     % The name of the push service. Currently, only
                               % `apns' (Apple Push) and `gcm' (Google Cloud
                               % Messaging) are known identifiers.

-type token() :: binary().     % The push token (APNS) or registration id (GCM)
                               % of the device + app being registered.
                               % The format of this is a binary string of the
                               % values provided by APNS or GCM, namely a lower
                               % case hex string (AONS) and a very long text
                               % string returned by GCM.

-type app_id() :: binary().    % An application id, e.g. `<<"com.example.foo">>'.
-type dist() :: binary().      % A distribution, `<<"prod">>' or `<<"dev">>'.

-type created_on() :: erlang:timestamp().
-type mod_time() :: erlang:timestamp().
-type inv_time() :: undefined | erlang:timestamp().

-type reg_db_props() :: [{'app_id', app_id()} |
                         {'dist', dist()} |
                         {'service', service()} |
                         {'device_id', device_id()} |
                         {'tag', tag()} |
                         {'modified', mod_time()} |
                         {'created_on', created_on()} |
                         {'last_invalid_on', inv_time()} |
                         {'token', token()}].

-type mult_reg_db_props() :: [reg_db_props()].

%%--------------------------------------------------------------------
%% Keys used to retrieve push registrations from the database.
%%--------------------------------------------------------------------
-type device_id_key()   :: device_id().           % Device ID key.
-type reg_id_key()      :: {device_id(), tag()}.  % Registration ID key.
-type svc_tok_key()     :: {service(), token()}.  % Service/Token key.
-type tag_key()         :: tag().

-type device_id_keys()  :: [device_id()].         % List of device ID keys.
-type reg_id_keys()     :: [reg_id_key()].        % A list of registration id keys.
-type svc_tok_keys()    :: [svc_tok_key()].       % A list of service/Token keys.
-type tag_keys()        :: [tag_keys()].

-type last_invalid_ts() :: posix_timestamp_milliseconds().

-type svc_tok_ts()      :: {svc_tok_key(), last_invalid_ts()}.
-type mult_svc_tok_ts() :: [svc_tok_ts()].

-type rereg_id()        :: {reg_id_key(), NewTok :: token()}.
-type rereg_ids()       :: [rereg_id()].

-type rereg_svc_tok()   :: {svc_tok_key(), NewTok :: token()}.
-type rereg_svc_toks()  :: [rereg_svc_tok()].

-type err_disconnected() :: {error, disconnected}.
-type reg_db_result(Result) :: Result | err_disconnected().
-type db_props_result() :: reg_db_result(reg_db_props()) .
-type mult_db_props_result() :: reg_db_result(mult_reg_db_props()).
-type simple_result() :: reg_db_result(ok | {error, term()}).
-type db_props_lookup_result() :: reg_db_result(mult_reg_db_props() | notfound).

-export_type([
              app_id/0,
              atom_or_str/0,
              atomable/0,
              binable/0,
              db_props_result/0,
              db_props_lookup_result/0,
              device_id/0,
              dist/0,
              err_disconnected/0,
              inv_time/0,
              mod_time/0,
              created_on/0,
              mult_db_props_result/0,
              mult_reg_db_props/0,
              mult_svc_tok_ts/0,
              reg_db_props/0,
              reg_db_result/1,
              reg_id_key/0,
              reg_id_keys/0,
              service/0,
              svc_tok_key/0,
              tag/0,
              token/0
             ]).

-type ctx() :: undefined | term().

-define(S, ?MODULE).
-record(?S, {db_mod :: atom(),
             db_config = [] :: proplists:proplist(),
             db_ctx = undefined :: ctx(),
             start_args :: proplists:proplist(),
             delay = ?INITIAL_DELAY :: pos_integer(),
             timer = undefined :: undefined | timer:tref()
            }).

-type state() :: #?S{}.

%%--------------------------------------------------------------------
%% Behavior callbacks
%%--------------------------------------------------------------------
-callback db_init(Config) -> {ok, Context} | {error, Reason} when
      Config :: proplists:proplist(), Context :: ctx(),
      Reason :: term().


-callback db_info(Context) -> Result when
      Context :: ctx(),
      Result :: reg_db_result(proplists:proplist()).

-callback db_terminate(Context) -> Result when
      Context :: ctx(), Result :: reg_db_result(ok).


-callback delete_push_regs_by_device_ids(Context, DevIdKeys) -> Result when
      Context :: ctx(), DevIdKeys :: device_id_keys(),
      Result :: simple_result().


-callback delete_push_regs_by_ids(Context, RegIdKeys) -> Result when
      Context :: ctx(), RegIdKeys :: reg_id_keys(), Result :: simple_result().


-callback delete_push_regs_by_svc_toks(Context, SvcTokKeys) -> Result when
      Context :: ctx(), SvcTokKeys :: svc_tok_keys(),
      Result :: simple_result().

-callback update_invalid_timestamps_by_svc_toks(Context,
                                                SvcTokTsList) -> Result when
      Context :: ctx(), SvcTokTsList :: mult_svc_tok_ts(),
      Result :: simple_result().


-callback delete_push_regs_by_tags(Context, Tags) -> Result when
      Context :: ctx(), Tags :: tag_keys(), Result :: simple_result().


-callback get_registration_info_by_device_id(Context, DeviceId) -> Result when
      Context :: ctx(), DeviceId :: device_id_key(),
      Result :: db_props_lookup_result().


-callback get_registration_info_by_id(Context, RegId) -> Result when
      Context :: ctx(), RegId :: reg_id_key(),
      Result :: db_props_lookup_result().


-callback get_registration_info_by_svc_tok(Context, SvcTok) -> Result when
      Context :: ctx(), SvcTok :: svc_tok_key(),
      Result :: db_props_lookup_result().


-callback get_registration_info_by_tag(Context, Tag) -> Result when
      Context :: ctx(), Tag :: tag_key(),
      Result :: db_props_lookup_result().


-callback is_valid_push_reg(Context, PushReg) -> Result when
      Context :: ctx(), PushReg :: reg_db_props(),
      Result :: reg_db_result(boolean()).


-callback reregister_ids(Context, Ids) -> Result when
      Context :: ctx(), Ids :: rereg_ids(),
      Result :: reg_db_result(ok).


-callback reregister_svc_toks(Context, ReregSvcToks) -> Result when
      Context :: ctx(), ReregSvcToks :: rereg_svc_toks(),
      Result :: reg_db_result(ok).


-callback save_push_regs(Context, ListOfRegs) -> Result when
      Context :: ctx(), ListOfRegs :: [reg_db_props(), ...],
      Result :: simple_result().

-callback all_reg(Context) -> Result when
      Context :: ctx(), Result :: reg_db_result(list()).

-callback all_registration_info(Context) -> Result when
      Context :: ctx(), Result :: mult_reg_db_props().


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
-spec all_registration_info(pid()) -> mult_reg_db_props().
all_registration_info(Worker) ->
    gen_server:call(Worker, all_registration_info).

%%--------------------------------------------------------------------
%% @private
%% @deprecated For debug only.
%% @doc Return a list of all push registration "records".
%%
%% The format of the record is backend-specific (e.g. map(), record,
%% proplist, ...)
%% @end
%%--------------------------------------------------------------------
-spec all_reg(pid()) -> list().
all_reg(Worker) ->
    gen_server:call(Worker, all_reg).

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
    mult_reg_db_props() | notfound.
get_registration_info_by_device_id(Worker, DeviceID) ->
    gen_server:call(Worker, {get_registration_info_by_device_id, DeviceID}).

%%--------------------------------------------------------------------
%% @doc Get registration information by unique id.
%% @see:sc_push_reg_api: make_id/2
-spec get_registration_info_by_id(pid(), reg_id_key()) ->
    mult_reg_db_props() | notfound.
get_registration_info_by_id(Worker, ID) ->
    gen_server:call(Worker, {get_registration_info_by_id, ID}).

%%--------------------------------------------------------------------
%% @doc Get registration information by service-token.
%% @see sc_push_reg_api:make_svc_tok/2
-spec get_registration_info_by_svc_tok(pid(), svc_tok_key()) ->
    mult_reg_db_props() | notfound.
get_registration_info_by_svc_tok(Worker, SvcTok) ->
    gen_server:call(Worker, {get_registration_info_by_svc_tok, SvcTok}).

%%--------------------------------------------------------------------
%% @doc Get registration information by tag.
-spec get_registration_info_by_tag(pid(), binary()) ->
    mult_reg_db_props() | notfound.
get_registration_info_by_tag(Worker, Tag) ->
    gen_server:call(Worker, {get_registration_info_by_tag, Tag}).

%%--------------------------------------------------------------------
%% @doc Is push registration proplist valid?
-spec is_valid_push_reg(pid(), reg_db_props()) -> boolean().
is_valid_push_reg(Worker, PL) ->
    gen_server:call(Worker, {is_valid_push_reg, PL}).

%%--------------------------------------------------------------------
%% @doc Save a list of push registrations.
-spec save_push_regs(Worker, ListOfPropLists) -> ok | {error, term()} when
      Worker :: pid(), ListOfPropLists :: [reg_db_props(), ...].
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
%% @equiv make_sc_push_props(Service, Token, DeviceId, Tag, AppId,
%%                           Dist, LastModifiedOn, undefined)
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
%% @equiv make_sc_push_props(Service, Token, DeviceId, Tag, AppId,
%%                           Dist, LastModifiedOn, LastInvalidOn,
%%                           erlang:timestamp())
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
%% Portions of the code below were adapted - with thanks - from
%% https://github.com/epgsql/pgapp.git, specifically those related to
%% handling connection failure.
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
    {ok, connect(#?S{start_args=Args})}.

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

handle_call(_Req, _From, #?S{db_ctx=undefined}=St)->
    {reply, {error, disconnected}, St};
handle_call({save_push_regs, ListOfProplists}, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St)->
    Reply = Mod:save_push_regs(Ctx, ListOfProplists),
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
handle_call(all_registration_info, _From,
            #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:all_registration_info(Ctx),
    {reply, Reply, St};
handle_call(all_reg, _From, #?S{db_mod=Mod, db_ctx=Ctx}=St) ->
    Reply = Mod:all_reg(Ctx),
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

handle_cast(reconnect, State) ->
    {noreply, connect(State)};
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
handle_info({'EXIT', From, Reason}, St) ->
    {NewDelay, TRef} = case St#?S.timer of
                           undefined -> % no active timer
                               reconnect_after(St#?S.delay);
                           Timer ->
                               {St#?S.delay, Timer}
                       end,
    lager:warning("~p EXIT from ~p: ~p - attempting to reconnect in ~p ms~n",
                  [self(), From, Reason, NewDelay]),
    {noreply, St#?S{db_ctx=undefined, delay=NewDelay, timer=TRef}};
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
terminate(shutdown, #?S{db_mod=Mod, db_ctx=Ctx}) when Ctx =/= undefined ->
    lager:debug("~p terminated via shutdown", [Mod]),
    (catch Mod:db_terminate(Ctx));
terminate(Reason, St) ->
    lager:warning("~p ~p with unknown db shutdown status",
                  [St#?S.db_mod, Reason]).

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

%%--------------------------------------------------------------------
-spec connect(State) -> NewState when
      State :: state(), NewState :: state().
connect(#?S{delay=Delay, start_args=Args}=St) ->
    DbMod = sc_util:req_val(db_mod, Args),
    DbConfig = sc_util:req_val(db_config, Args),
    case DbMod:db_init(DbConfig) of
        {ok, DbCtx} ->
            timer:cancel(St#?S.timer),
            St#?S{db_ctx=DbCtx,
                  db_mod=DbMod,
                  db_config=DbConfig,
                  delay=?INITIAL_DELAY,
                  timer=undefined};
        Error ->
            lager:warning("Error connecting via ~p: ~p, "
                          "reconnecting in ~B ms",
                          [DbMod, Error, Delay]),
            {NewDelay, TRef} = reconnect_after(Delay),
            St#?S{db_ctx=undefined,
                  db_mod=DbMod,
                  db_config=DbConfig,
                  delay=NewDelay,
                  timer=TRef}
    end.

%%--------------------------------------------------------------------
-spec reconnect_after(DelayMs) -> Result when
      DelayMs :: pos_integer(), Result :: {NewDelayMs, TRef},
      TRef :: timer:tref(), NewDelayMs :: pos_integer().
reconnect_after(DelayMs) ->
    {ok, TRef} = timer:apply_after(DelayMs,
                                   gen_server, cast, [self(), reconnect]),
    {calculate_delay(DelayMs), TRef}.

%%--------------------------------------------------------------------
calculate_delay(Delay) when (Delay * 2) >= ?MAXIMUM_DELAY ->
    ?MAXIMUM_DELAY;
calculate_delay(Delay) ->
    Delay * 2.
