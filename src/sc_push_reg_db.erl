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

-module(sc_push_reg_db).

-behavior(gen_server).

-export([
         start_link/0,
         start/0
        ]).

-export([
         all_reg/0,
         all_registration_info/0,
         check_id/1,
         check_ids/1,
         create_tables/1,
         delete_push_regs_by_device_ids/1,
         delete_push_regs_by_ids/1,
         delete_push_regs_by_svc_toks/1,
         delete_push_regs_by_tags/1,
         update_invalid_timestamps_by_svc_toks/1,
         get_registration_info_by_device_id/1,
         get_registration_info_by_id/1,
         get_registration_info_by_svc_tok/1,
         get_registration_info_by_tag/1,
         is_valid_push_reg/1,
         make_id/2,
         make_sc_push_props/7,
         make_sc_push_props/8,
         make_svc_tok/2,
         reregister_ids/1,
         reregister_svc_toks/1,
         save_push_regs/1,
         from_posix_time_ms/1
        ]).

%% gen_server callbacks
-export([init/1,
         handle_call/3,
         handle_cast/2,
         handle_info/2,
         terminate/2,
         code_change/3]).

-define(SERVER, ?MODULE).

-type terminate_reason() :: normal |
                            shutdown |
                            {shutdown, term()} |
                            term().

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
                         {'last_invalid_on', tuple()} |
                         {'token', binary()}].


-export_type([
        reg_id_key/0,
        svc_tok_key/0,
        atom_or_str/0,
        atomable/0,
        binable/0,
        reg_id_keys/0,
        reg_db_props/0
        ]).

-define(S, ?MODULE).
-record(?S, {db_mod, db_config}).

-type state() :: #?S{}.

%%--------------------------------------------------------------------
%% Behavior callbacks
%%--------------------------------------------------------------------
-callback db_init(Config) -> ok | {error, Reason}
    when Config :: term(), Reason :: term().


-callback db_info() -> Info
    when Info :: proplists:proplist().


-callback db_terminate() -> ok.


-callback all_reg() -> Result
    when Result :: push_reg_list().


-callback all_registration_info() -> Result
    when Result :: [sc_types:reg_proplist()].


-callback check_id(RegIdKey) -> Result
    when RegIdKey :: reg_id_key(), Result :: reg_id_key().


-callback check_ids(RegIdKeys) -> Result
    when RegIdKeys :: reg_id_keys(), Result :: reg_id_keys().


-callback create_tables(Config) -> any()
    when Config :: any().


-callback delete_push_regs_by_device_ids(Key) -> Result
    when Key :: term(), Result :: term().


-callback delete_push_regs_by_ids(Key) -> Result
    when Key :: term(), Result :: term().


-callback delete_push_regs_by_svc_toks(Key) -> Result
    when Key :: term(), Result :: term().


-callback update_invalid_timestamps_by_svc_toks(Key) -> Result
    when Key :: term(), Result :: term().


-callback delete_push_regs_by_tags(Key) -> Result
    when Key :: term(), Result :: term().


-callback get_registration_info_by_device_id(Key) -> Result
    when Key :: term(), Result :: term().


-callback get_registration_info_by_id(Key) -> Result
    when Key :: term(), Result :: term().


-callback get_registration_info_by_svc_tok(Key) -> Result
    when Key :: term(), Result :: term().


-callback get_registration_info_by_tag(Key) -> Result
    when Key :: term(), Result :: term().


-callback is_valid_push_reg(Key) -> Result
    when Key :: term(), Result :: term().


-callback reregister_ids(Ids) -> ok
    when Ids :: [{reg_id_key(), binary()}].


-callback reregister_svc_toks(SvcToks) -> ok
    when SvcToks :: [{svc_tok_key(), binary()}].


-callback save_push_regs(ListOfProplists) -> Result
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
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc
%% Start the server without linking (for debugging and testing).
%%
%% @end
%%--------------------------------------------------------------------
-spec start() -> {ok, pid()} | ignore | {error, term()}.
start() ->
    gen_server:start({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc Return a list of property lists of all registrations.
%% @deprecated For debug only
-spec all_registration_info() -> [sc_types:reg_proplist()].
all_registration_info() ->
    gen_server:call(?SERVER, all_registration_info).

%%--------------------------------------------------------------------
%% @doc Return a list of all push registration records.
%% @deprecated For debug only.
-spec all_reg() -> push_reg_list().
all_reg() ->
    gen_server:call(?SERVER, all_reg).

%%--------------------------------------------------------------------
%% @doc Check registration id key.
-spec check_id(reg_id_key()) -> reg_id_key().
check_id(ID) ->
    gen_server:call(?SERVER, {check_id, ID}).

%%--------------------------------------------------------------------
%% @doc Check multiple registration id keys.
-spec check_ids(reg_id_keys()) -> reg_id_keys().
check_ids(IDs) ->
    gen_server:call(?SERVER, {check_ids, IDs}).

%%--------------------------------------------------------------------
%% @doc Create tables. May be a no-op for certain backends.
create_tables(Config) ->
    gen_server:call(?SERVER, {create_tables, Config}).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by device ids
-spec delete_push_regs_by_device_ids([binary()]) -> ok | {error, term()}.
delete_push_regs_by_device_ids(DeviceIDs) ->
    gen_server:call(?SERVER, {delete_push_regs_by_device_ids, DeviceIDs}).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by internal registration id.
-spec delete_push_regs_by_ids(reg_id_keys()) -> ok | {error, term()}.
delete_push_regs_by_ids(IDs) ->
    gen_server:call(?SERVER, {delete_push_regs_by_ids, IDs}).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by service-token.
-spec delete_push_regs_by_svc_toks([svc_tok_key()]) -> ok | {error, term()}.
delete_push_regs_by_svc_toks(SvcToks) ->
    gen_server:call(?SERVER, {delete_push_regs_by_svc_toks, SvcToks}).

%%--------------------------------------------------------------------
%% @doc Update push registration invalid timestamp by service-token.
-spec update_invalid_timestamps_by_svc_toks([{svc_tok_key(), non_neg_integer()}]) -> ok | {error, term()}.
update_invalid_timestamps_by_svc_toks(SvcToksTs) ->
    gen_server:call(?SERVER, {update_invalid_timestamps_by_svc_toks, SvcToksTs}).

%%--------------------------------------------------------------------
%% @doc Delete push registrations by tags.
-spec delete_push_regs_by_tags([binary()]) -> ok | {error, term()}.
delete_push_regs_by_tags(Tags) ->
    gen_server:call(?SERVER, {delete_push_regs_by_tags, Tags}).

%%--------------------------------------------------------------------
%% @doc Get registration information by device id.
-spec get_registration_info_by_device_id(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_device_id(DeviceID) ->
    gen_server:call(?SERVER, {get_registration_info_by_device_id, DeviceID}).

%%--------------------------------------------------------------------
%% @doc Get registration information by unique id.
%% @see make_id/2
-spec get_registration_info_by_id(reg_id_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_id(ID) ->
    gen_server:call(?SERVER, {get_registration_info_by_id, ID}).

%%--------------------------------------------------------------------
%% @doc Get registration information by service-token.
%% @see make_svc_tok/2
-spec get_registration_info_by_svc_tok(svc_tok_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_svc_tok(SvcTok) ->
    gen_server:call(?SERVER, {get_registration_info_by_svc_tok, SvcTok}).

%%--------------------------------------------------------------------
%% @doc Get registration information by tag.
-spec get_registration_info_by_tag(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(Tag) ->
    gen_server:call(?SERVER, {get_registration_info_by_tag, Tag}).

%%--------------------------------------------------------------------
%% @doc Is push registration proplist valid?
-spec is_valid_push_reg(sc_types:proplist(atom(), term())) -> boolean().
is_valid_push_reg(PL) ->
    gen_server:call(?SERVER, {is_valid_push_reg, PL}).

%%--------------------------------------------------------------------
%% @doc Save a list of push registrations.
-spec save_push_regs([sc_types:reg_proplist(), ...]) -> ok | {error, term()}.
save_push_regs(ListOfProplists) ->
    gen_server:call(?SERVER, {save_push_regs, ListOfProplists}).

%%--------------------------------------------------------------------
%% @doc Re-register invalidated tokens
-spec reregister_ids([{reg_id_key(), binary()}]) -> ok.
reregister_ids(IDToks) ->
    gen_server:call(?SERVER, {reregister_ids, IDToks}).

%%--------------------------------------------------------------------
%% @doc Re-register invalidated tokens by svc_tok
-spec reregister_svc_toks([{svc_tok_key(), binary()}]) -> ok.
reregister_svc_toks(SvcToks) ->
    gen_server:call(?SERVER, {reregister_svc_toks, SvcToks}).

%%--------------------------------------------------------------------
%% @doc Convert to an opaque registration ID key.
-spec make_id(binable(), binable()) -> reg_id_key().
make_id(Id, Tag) ->
    case {sc_util:to_bin(Id), sc_util:to_bin(Tag)} of
        {<<_,_/binary>>, <<_,_/binary>>} = Key ->
            Key;
        _IdTag ->
            throw({invalid_id_or_tag, {Id, Tag}})
    end.

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
                   LastModifiedOn) ->
    LastInvalidOn = {0, 0, 0},
    make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                       LastModifiedOn, LastInvalidOn).

%%--------------------------------------------------------------------
%% @doc Create a property list from push registration data.
-spec make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist,
                         LastModifiedOn, LastInvalidOn) -> Result
    when
      Service :: atomable(), Token :: binable(), DeviceId :: binable(),
      Tag :: binable(), AppId :: binable(), Dist :: binable(),
      LastModifiedOn :: erlang:timestamp(), LastInvalidOn :: erlang:timestamp(),
      Result :: reg_db_props()
      .
make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist, LastModifiedOn,
                   LastInvalidOn) ->
    [
        {device_id, sc_util:to_bin(DeviceId)},
        {service, sc_util:to_atom(Service)},
        {token, sc_util:to_bin(Token)},
        {tag, sc_util:to_bin(Tag)},
        {app_id, sc_util:to_bin(AppId)},
        {dist, sc_util:to_bin(Dist)},
        {modified, LastModifiedOn},
        {last_invalid_on, LastInvalidOn}
    ].

%%--------------------------------------------------------------------
%% @doc Convert to an opaque service-token key.
-spec make_svc_tok(atom_or_str(), binable()) -> svc_tok_key().
make_svc_tok(Service, Token) when is_atom(Service) ->
    {Service, sc_util:to_bin(Token)};
make_svc_tok(Service, Token) when is_list(Service) ->
    make_svc_tok(list_to_atom(Service), Token).

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
init([]) ->
    erlang:process_flag(trap_exit, true),
    {ok, App} = application:get_application(?MODULE),
    DbMod = application:get_env(App, db_mod, sc_push_reg_db_mnesia),
    _ = lager:info("Push registration db module is ~p", [DbMod]),
    DbConfig = application:get_env(App, db_config, [node()]),
    _ = lager:info("Push registration db config is ~p", [DbConfig]),
    case DbMod:db_init(DbConfig) of
        ok ->
            _ = lager:info("DB module ~p is initialized", [DbMod]),
            State = #?S{db_mod=DbMod, db_config=DbConfig},
            {ok, State};
        Error ->
            _ = lager:error("~p:db_init/1 failed with config ~p",
                            [DbMod, DbConfig]),
            {stop, {DbMod, db_init, DbConfig, Error}}
    end.

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

handle_call(all_registration_info, _From, St) ->
    Reply = (St#?S.db_mod):all_registration_info(),
    {reply, Reply, St};
handle_call(all_reg, _From, St) ->
    Reply = (St#?S.db_mod):all_reg(),
    {reply, Reply, St};
handle_call({check_id, ID}, _From, St) ->
    Reply = (St#?S.db_mod):check_id(ID),
    {reply, Reply, St};
handle_call({check_ids, IDs}, _From, St) ->
    Reply = (St#?S.db_mod):check_ids(IDs),
    {reply, Reply, St};
handle_call({create_tables, Config}, _From, St) ->
    Reply = (St#?S.db_mod):create_tables(Config),
    {reply, Reply, St};
handle_call({delete_push_regs_by_device_ids, DeviceIDs}, _From, St) ->
    Reply = (St#?S.db_mod):delete_push_regs_by_device_ids(DeviceIDs),
    {reply, Reply, St};
handle_call({delete_push_regs_by_ids, IDs}, _From, St) ->
    Reply = (St#?S.db_mod):delete_push_regs_by_ids(IDs),
    {reply, Reply, St};
handle_call({delete_push_regs_by_svc_toks, SvcToks}, _From, St) ->
    Reply = (St#?S.db_mod):delete_push_regs_by_svc_toks(SvcToks),
    {reply, Reply, St};
handle_call({delete_push_regs_by_tags, Tags}, _From, St) ->
    Reply = (St#?S.db_mod):delete_push_regs_by_tags(Tags),
    {reply, Reply, St};
handle_call({update_invalid_timestamps_by_svc_toks, SvcToksTs}, _From, St) ->
    Reply = (St#?S.db_mod):update_invalid_timestamps_by_svc_toks(SvcToksTs),
    {reply, Reply, St};
handle_call({get_registration_info_by_device_id, DeviceID}, _From, St) ->
    Reply = (St#?S.db_mod):get_registration_info_by_device_id(DeviceID),
    {reply, Reply, St};
handle_call({get_registration_info_by_id, ID}, _From, St) ->
    Reply = (St#?S.db_mod):get_registration_info_by_id(ID),
    {reply, Reply, St};
handle_call({get_registration_info_by_svc_tok, SvcTok}, _From, St) ->
    Reply = (St#?S.db_mod):get_registration_info_by_svc_tok(SvcTok),
    {reply, Reply, St};
handle_call({get_registration_info_by_tag, Tag}, _From, St) ->
    Reply = (St#?S.db_mod):get_registration_info_by_tag(Tag),
    {reply, Reply, St};
handle_call({save_push_regs, ListOfProplists}, _From, St) ->
    Reply = (St#?S.db_mod):save_push_regs(ListOfProplists),
    {reply, Reply, St};
handle_call({is_valid_push_reg, PL}, _From, St) ->
    Reply = (St#?S.db_mod):is_valid_push_reg(PL),
    {reply, Reply, St};
handle_call({reregister_ids, IdToks}, _From, St) ->
    Reply = (St#?S.db_mod):reregister_ids(IdToks),
    {reply, Reply, St};
handle_call({reregister_svc_toks, SvcToks}, _From, St) ->
    Reply = (St#?S.db_mod):reregister_svc_toks(SvcToks),
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
terminate(shutdown, St) ->
    lager:info("~p terminated via shutdown", [St#?S.db_mod]),
    (catch (St#?S.db_mod):db_terminate());
terminate(Reason, St) ->
    lager:info("~p terminated for reason ~p", [St#?S.db_mod, Reason]).

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

