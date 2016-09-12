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

%%%-------------------------------------------------------------------
%%% @author Edwin Fine
%%% @copyright (C) 2012,2013 Silent Circle LLC
%%% @doc
%%% Configuration server for sc_push.
%%% @end
%%% Created : 2012-12-07 17:03:31.766445
%%%-------------------------------------------------------------------
-module(sc_config).

-behaviour(gen_server).

%% API
-export([start_link/0, set/2, get/1, get/2, delete/1]).

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

-record(sc_config, {key, value}).

-record(state, {}).

%%%===================================================================
%%% API
%%%===================================================================
%% @doc Set key/value pair.
-spec set(term(), term()) -> ok.
set(K, V) ->
    gen_server:call(?SERVER, {set, {K, V}}).

%% @doc Get value for key, or undefined is not found.
-spec get(term()) -> term() | undefined.
get(K) ->
    gen_server:call(?SERVER, {get, K}).

%% @doc Get value for key, or default value if key not found.
-spec get(term(), term()) -> term().
get(K, Def) ->
    case ?MODULE:get(K) of
        undefined ->
            Def;
        V ->
            V
    end.

%% @doc Delete key.
-spec delete(term()) -> ok.
delete(K) ->
    gen_server:call(?SERVER, {delete, K}).

%%--------------------------------------------------------------------
%% @doc
%% Starts the server
%%
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%%===================================================================
%%% gen_server callbacks
%%%===================================================================

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Initializes the server
%%
%% @end
%%--------------------------------------------------------------------
-spec init(term()) -> {ok, State::term()} |
                      {ok, State::term(), Timeout::timeout()} |
                      {ok, State::term(), 'hibernate'} |
                      {stop, Reason::term()} |
                      'ignore'
                      .
init([]) ->
    create_tables([node()]),
    {ok, #state{}}.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Handling call messages
%%
%% @end
%%--------------------------------------------------------------------
-spec handle_call(Request::term(),
                  From::{pid(), Tag::term()},
                  State::term()) ->
    {reply, Reply::term(), NewState::term()} |
    {reply, Reply::term(), NewState::term(), Timeout::timeout()} |
    {reply, Reply::term(), NewState::term(), 'hibernate'} |
    {noreply, NewState::term()} |
    {noreply, NewState::term(), 'hibernate'} |
    {noreply, NewState::term(), Timeout::timeout()} |
    {stop, Reason::term(), Reply::term(), NewState::term()} |
    {stop, Reason::term(), NewState::term()}
    .

handle_call({set, {K, V}}, _From, State) ->
    Reply = set_config(K, V),
    {reply, Reply, State};
handle_call({get, K}, _From, State) ->
    Reply = get_config(K),
    {reply, Reply, State};
handle_call({delete, K}, _From, State) ->
    Reply = delete_config(K),
    {reply, Reply, State};
handle_call(_Request, _From, State) ->
    Reply = {error, bad_request},
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
                  State::term()) ->
    {noreply, NewState::term()} |
    {noreply, NewState::term(), 'hibernate'} |
    {noreply, NewState::term(), Timeout::timeout()} |
    {stop, Reason::term(), NewState::term()}
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
                  State::term()) ->
    {noreply, NewState::term()} |
    {noreply, NewState::term(), 'hibernate'} |
    {noreply, NewState::term(), Timeout::timeout()} |
    {stop, Reason::term(), NewState::term()}
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
                State::term()) -> no_return().
terminate(_Reason, _State) ->
    ok.

%%--------------------------------------------------------------------
%% @private
%% @doc
%% Convert process state when code is changed
%%
%% @end
%%--------------------------------------------------------------------
-spec code_change(OldVsn::term() | {down, term()},
                  State::term(),
                  Extra::term()) ->
    {ok, NewState::term()} |
    {error, Reason::term()}.
code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%%%===================================================================
%%% Internal functions
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc Create local config DB
%% @end
%%--------------------------------------------------------------------
create_tables(Nodes) ->
    Res = mnesia:create_table(sc_config,
        [
            {ram_copies, Nodes},
            {type, set},
            {attributes, record_info(fields, sc_config)},
            {local_content, true}
        ]
    ),
    case Res of
        {atomic, ok} ->
            ok;
        {aborted, {already_exists, _}} ->
                ok
    end.

set_config(K, V) ->
    ok = mnesia:dirty_write(#sc_config{key = K, value = V}).

get_config(K) ->
    case mnesia:dirty_read(sc_config, K) of
        [] ->
            undefined;
        [R] ->
            R#sc_config.value
    end.

delete_config(K) ->
    mnesia:dirty_delete({sc_config, K}).

