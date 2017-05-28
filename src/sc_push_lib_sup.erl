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
           [?CHILD(sc_push_reg_api, supervisor),
            ?CHILD(sc_config, worker),
            ?CHILD(sc_push_req_mgr, worker)
           ]}
    }.

-spec internal_db_init() -> Result when
      Result :: {ok, Dir}, Dir :: string().
internal_db_init() ->
    Me = node(),
    Dir = mnesia_dir(Me),
    lager:debug("Mnesia database dir: ~p", [Dir]),
    lager:debug("Initializing mnesia database on ~p", [Me]),

    ensure_schema(Me),
    ensure_correct_node(Me, mnesia:system_info(db_nodes)),
    lager:info("Starting mnesia database in dir ~p on node ~p", [Dir, Me]),
    ok = mnesia:start(),
    lager:info("Waiting for mnesia tables on node ~p", [Me]),
    mnesia:wait_for_tables(mnesia:system_info(local_tables), infinity),
    lager:info("Mnesia database started on ~p", [Me]),
    mnesia:stop(),
    {ok, Dir}.


ensure_correct_node(Node, DbNodes) ->
    case lists:member(Node, DbNodes) of
        true ->
            ok;
        false ->
            lager:error("Node name mismatch: This node is [~s], "
                        "the database is owned by ~p", [Node, DbNodes]),
            erlang:error(node_name_mismatch)
    end.

ensure_schema(Node) ->
    case mnesia:system_info(use_dir) of % Is there a disc-based schema?
        false ->
            lager:info("About to create mnesia schema on ~p", [Node]),
            mnesia:stop(),
            case mnesia:create_schema([Node]) of
                ok ->
                    lager:info("Created mnesia database schema on ~p", [Node]);
                {error, {Node, {already_exists, Node}}} ->
                    lager:debug("mnesia schema already exists on ~p", [Node])
            end;
        true ->
            ok
    end,
    mnesia:start(),
    case mnesia:table_info(schema, disc_copies) of
        [] ->
            {atomic, ok} = mnesia:change_table_copy_type(schema, Node,
                                                         disc_copies);
        [_|_] = L ->
            true = lists:member(Node, L)
    end,
    mnesia:stop().

mnesia_dir(Node) ->
    case application:get_env(mnesia, dir) of
        undefined ->
            D = "Mnesia." ++ atom_to_list(Node),
            application:set_env(mnesia, dir, D),
            D;
        {ok, D} ->
            D
    end.
