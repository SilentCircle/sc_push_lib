%%%-------------------------------------------------------------------
%%% @author Edwin Fine
%%% @copyright (C) 2012,2013 Silent Circle LLC
%%% @doc
%%% @end
%%%-------------------------------------------------------------------
-module(sc_push_req_mgr).

-behaviour(gen_server).

%%====================================================================
%% API Exports
%%====================================================================
-export([
        start_link/0,
        add/2,
        all_req/0,
        lookup/1,
        remove/1,
        remove_all/0,
        sweep/0,
        sweep/1,
        sync_sweep/0,
        sync_sweep/1,
        default_callback/1
    ]).

%%====================================================================
%% gen_server callback exports
%%====================================================================
-export([init/1,
        handle_call/3,
        handle_cast/2,
        handle_info/2,
        terminate/2,
        code_change/3]).

%%--------------------------------------------------------------------
%% Includes
%%--------------------------------------------------------------------
-include("sc_push_lib.hrl").
-include_lib("lager/include/lager.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

%%--------------------------------------------------------------------
%% Defines
%%--------------------------------------------------------------------
-define(SERVER, ?MODULE).

-define(DEFAULT_MAX_AGE_SECS, (5 * ?MINUTES)).
-define(DEFAULT_SWEEP_INTERVAL, (60 * ?SECONDS)).

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-type terminate_reason() :: normal |
                            shutdown |
                            {shutdown, term()} |
                            term().

%%--------------------------------------------------------------------
%% `req_prop()' may be any of the following:
%%
%% <dl>
%%   <dt>`{id, term()}'</dt>
%%      <dd>Request identity, must be unique.</dd>
%%   <dt>`{req, term()}'</dt>
%%      <dd>The actual request - can be anything, really.</dd>
%%   <dt>`{ts, posix_time()}'</dt>
%%      <dd>POSIX timestamp of when the request was stored.</dd>
%%   <dt>`{callback, fun()}'</dt>
%%      <dd>Callback function invoked after request completes.
%%          Currently unused.</dd>
%% </dl>
%%--------------------------------------------------------------------
-type req_prop() :: sc_util:prop(atom(), term()).
-type req_props() :: [req_prop()].

%%--------------------------------------------------------------------
%% Records
%%--------------------------------------------------------------------
-record(reqinfo, {id, ts, req, callback}).

-record(state, {
        max_age_secs    = ?DEFAULT_MAX_AGE_SECS,
        sweep_interval  = ?DEFAULT_SWEEP_INTERVAL,
        sweep_timer_ref = undefined
    }).

%%%===================================================================
%%% API
%%%===================================================================

%%--------------------------------------------------------------------
%% @doc
%% Start the server.
%% @end
%%--------------------------------------------------------------------
-spec start_link() -> {ok, pid()} | ignore | {error, term()}.
start_link() ->
    gen_server:start_link({local, ?SERVER}, ?MODULE, [], []).

%%--------------------------------------------------------------------
%% @doc Add a request.
%% @end
%%--------------------------------------------------------------------
-spec add(Id :: term(), Req :: term()) -> ok.
add(Id, Req) ->
    gen_server:call(?SERVER, {add, Id, Req}).

%%--------------------------------------------------------------------
%% @doc Return all requests as a list of proplists.
%% @end
%%--------------------------------------------------------------------
-spec all_req() -> [req_props()].
all_req() ->
    gen_server:call(?SERVER, all_req).

%%--------------------------------------------------------------------
%% @doc
%% Lookup a request. 
%% @end
%%--------------------------------------------------------------------
-spec lookup(Id :: term()) -> Req :: req_props() | undefined.
lookup(Id) ->
    gen_server:call(?SERVER, {lookup, Id}).

%%--------------------------------------------------------------------
%% @doc Remove a request and return it if it was there, or undefined.
%% @end
%%--------------------------------------------------------------------
-spec remove(Id :: term()) -> Req :: req_props() | undefined.
remove(Id) ->
    gen_server:call(?SERVER, {remove, Id}).

%%--------------------------------------------------------------------
%% @doc Remove all requests.
%% @end
%%--------------------------------------------------------------------
-spec remove_all() -> ok.
remove_all() ->
    gen_server:call(?SERVER, remove_all).

%%--------------------------------------------------------------------
%% @doc Manually kick off a synchronous sweep for aged-out requests.
%% @end
%%--------------------------------------------------------------------
-spec sync_sweep() -> {ok, NumDeleted::non_neg_integer()}.
sync_sweep() ->
    gen_server:call(?SERVER, sweep).

%%--------------------------------------------------------------------
%% @doc Manually kick off a sync sweep for requests, specifying max age in
%% seconds. If max age is negative, all requests will be removed.
%% @end
%%--------------------------------------------------------------------
-spec sync_sweep(MaxAge::non_neg_integer()) -> {ok, NumDeleted::non_neg_integer()}.
sync_sweep(MaxAge) when is_integer(MaxAge), MaxAge >= 0 ->
    gen_server:call(?SERVER, {sweep, MaxAge}).

%%--------------------------------------------------------------------
%% @doc Manually kick off an asynchronous sweep for aged-out requests.
%% @end
%%--------------------------------------------------------------------
-spec sweep() -> ok.
sweep() ->
    ?SERVER ! sweep,
    ok.

%%--------------------------------------------------------------------
%% @doc Manually kick off a sync sweep for requests, specifying max age in
%% seconds. If max age is negative, all requests will be removed.
%% @end
%%--------------------------------------------------------------------
-spec sweep(MaxAge::non_neg_integer()) -> ok.
sweep(MaxAge) when is_integer(MaxAge), MaxAge >= 0 ->
    ?SERVER ! {sweep, MaxAge},
    ok.

%% @doc Default callback. Does nothing, returns ok.
default_callback(_Props) ->
    ok.

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
    create_tables(),
    State = #state{},
    TimerRef = schedule_sweeper(self(), State#state.sweep_interval),
    {ok, State#state{sweep_timer_ref = TimerRef}}.

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

handle_call({add, Id, Req}, _From, State) ->
    Reply = add_req(Id, Req, fun ?MODULE:default_callback/1),
    {reply, Reply, State};
handle_call(all_req, _From, State) ->
    Reply = all_req_impl(),
    {reply, Reply, State};
handle_call({lookup, Id}, _From, State) ->
    Reply = lookup_req(Id),
    {reply, Reply, State};
handle_call({remove, Id}, _From, State) ->
    Reply = remove_req(Id),
    {reply, Reply, State};
handle_call(remove_all, _From, State) ->
    Reply = remove_all_req(),
    {reply, Reply, State};
handle_call(sweep, _From, State) ->
    handle_call({sweep, State#state.max_age_secs}, _From, State);
handle_call({sweep, MaxAgeSecs}, _From, State) ->
    {TimerRef, NumDel} = do_sweep(self(),
                                  State#state.sweep_timer_ref,
                                  MaxAgeSecs,
                                  State#state.sweep_interval),
    Reply = {ok, NumDel},
    {reply, Reply, State#state{sweep_timer_ref = TimerRef}};
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
handle_info(sweep, State) ->
    handle_info({sweep, State#state.max_age_secs}, State);
handle_info({sweep, MaxAgeSecs}, State) ->
    {TimerRef, _} = do_sweep(self(),
                             State#state.sweep_timer_ref,
                             MaxAgeSecs,
                             State#state.sweep_interval),
    {noreply, State#state{sweep_timer_ref = TimerRef}};
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
terminate(_Reason, State) ->
    cancel_sweeper(State#state.sweep_timer_ref),
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

%% These functions must be called in the context of the gen_server.
create_tables() ->
    ets:new(reqinfo, [set, named_table, {keypos, #reqinfo.id}]).

add_req(Id, Req, Callback) when is_function(Callback, 1) ->
    ets:insert(reqinfo,
               #reqinfo{id = Id,
                        ts = sc_util:posix_time(),
                        req = Req,
                        callback = Callback}),
    ok.

all_req_impl() ->
    ets:foldr(fun(Req, Acc) -> [req_to_pl(Req) | Acc] end, [], reqinfo).

remove_req(Id) ->
    case lookup_req_internal(Id) of
        #reqinfo{} = RI ->
            ets:delete(reqinfo, Id),
            req_to_pl(RI);
        undefined ->
            undefined
    end.

remove_all_req() ->
    ets:delete_all_objects(reqinfo),
    ok.

lookup_req(Id) ->
    case lookup_req_internal(Id) of
        #reqinfo{} = RI ->
            req_to_pl(RI);
        undefined ->
            undefined
    end.

lookup_req_internal(Id) ->
    case ets:lookup(reqinfo, Id) of
        [#reqinfo{} = RI] ->
            RI;
        [] ->
            undefined
    end.

do_sweep(Pid, OldRef, MaxAgeSecs, SweepInterval) ->
    cancel_sweeper(OldRef),
    NumDel = sweep_impl(MaxAgeSecs),
    TimerRef = schedule_sweeper(Pid, SweepInterval),
    log_purged_reqs(NumDel),
    {TimerRef, NumDel}.

-spec sweep_impl(non_neg_integer()) -> NumDeleted::non_neg_integer().
sweep_impl(OlderThanSecs) ->
    Now = sc_util:posix_time(),
    MatchSpec = ets:fun2ms(fun(#reqinfo{ts = TS}) -> Now - TS >= OlderThanSecs end),
    ets:select_delete(reqinfo, MatchSpec).

%% These functions may be called by anything
req_to_pl(#reqinfo{} = RI) ->
    [
        {id, RI#reqinfo.id},
        {req, RI#reqinfo.req},
        {ts, RI#reqinfo.ts},
        {callback, RI#reqinfo.callback}
    ].

schedule_sweeper(Pid, WaitMs) ->
    erlang:send_after(WaitMs, Pid, sweep).

cancel_sweeper(undefined) ->
    ok;
cancel_sweeper(Ref) when is_reference(Ref) ->
    erlang:cancel_timer(Ref).

log_purged_reqs(0) ->
    ok;
log_purged_reqs(NumDel) when is_integer(NumDel) andalso NumDel > 0 ->
    lager:info("Purged ~B old requests", [NumDel]).
