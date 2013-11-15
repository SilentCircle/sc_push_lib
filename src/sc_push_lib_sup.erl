
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
    lager:info("Initializing push registration API", []),
    ok = sc_push_reg_api:init(),
    lager:info("Push registration API ready", []),
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    {ok, { {one_for_one, 5, 10}, [
                ?CHILD(sc_config, worker),
                ?CHILD(sc_push_req_mgr, worker)
            ]} }.

