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
    {ok, _MnesiaDir} = internal_db_init(),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, { {one_for_one, 5, 10},
           [?CHILD(sc_push_reg_db, worker),
            ?CHILD(sc_config, worker),
            ?CHILD(sc_push_req_mgr, worker)
           ]}
    }.

-spec internal_db_init() -> ok.
internal_db_init() ->
    Me = node(),
    Dir = case application:get_env(mnesia, dir) of
              undefined ->
                  D = "Mnesia." ++ atom_to_list(Me),
                  application:set_env(mnesia, dir, D),
                  D;
              {ok, D} ->
                  D
          end,
    lager:info("Mnesia database dir: ~p", [Dir]),
    lager:info("Initializing mnesia database on ~p", [Me]),

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
                    lager:info("Created mnesia database schema on ~p", [Me]);
                {error, {Me, {already_exists, Me}}} ->
                    lager:info("mnesia schema already exists on ~p", [Me])
            end;
        true ->
            lager:info("No mnesia schema creation required.")
    end,
    lager:info("Starting mnesia database in dir ~p on node ~p", [Dir, Me]),
    ok = mnesia:start(),
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),
    lager:info("Database initialized on ~p", [Me]),
    mnesia:stop(),
    {ok, Dir}.

