%%% ==========================================================================
%%% Copyright 2015, 2016 Silent Circle
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


-module(sc_push_lib_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

-include_lib("lager/include/lager.hrl").

%% Helper macro for declaring children of supervisor
-define(CHILD(I, Type), {I, {I, start_link, []}, permanent, 5000, Type, [I]}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    ok = db_init(),
    _ = lager:info("Initializing push registration API", []),
    ok = sc_push_reg_api:init(),
    _ = lager:info("Push registration API ready", []),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, { {one_for_one, 5, 10},
           [
            ?CHILD(sc_config, worker),
            ?CHILD(sc_push_req_mgr, worker)
           ]}
    }.

-spec db_init() -> ok.
db_init() ->
    Me = node(),
    lager:info("Initializing database on ~p", [Me]),
    mnesia:stop(),
    DbNodes = mnesia:system_info(db_nodes),
    case lists:member(Me, DbNodes) of
        true ->
            ok;
        false ->
            lager:error("Node name mismatch: This node is [~s], "
                        "the database is owned by ~p", [Me, DbNodes]),
            erlang:error(node_name_mismatch)
    end,
    case mnesia:system_info(use_dir) of % Is there a disc-based schema?
        false ->
            lager:info("About to create schema on ~p", [Me]),
            case mnesia:create_schema([Me]) of
                ok ->
                    lager:info("Created database schema on ~p", [Me]);
                {error, {Me, {already_exists, Me}}} ->
                    lager:info("Schema already exists on ~p", [Me])
            end;
        true ->
            lager:info("No schema creation required.")
    end,
    lager:info("Starting database on ~p", [Me]),
    ok = mnesia:start(),
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),
    lager:info("Database initialized on ~p", [Me]),
    ok.

