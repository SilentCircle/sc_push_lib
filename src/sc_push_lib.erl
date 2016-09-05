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
%%% @author Edwin Fine <efine@silentcircle.com>
%%% @copyright 2015, 2016 Silent Circle
%%% @doc
%%% Push service common library functions.
%%% @end
%%%-------------------------------------------------------------------
-module(sc_push_lib).

-export([
        register_service/1,
        unregister_service/1,
        get_service_config/1
    ]).

%%--------------------------------------------------------------------
%% @doc Register a service in the service configuration registry.
%% Requires a property `{name, ServiceName :: atom()}' to be present
%% in `Svc'.
%% @see start_service/1
%% @end
%%--------------------------------------------------------------------
-spec register_service(Svc) -> ok when
      Svc :: sc_types:proplist(atom(), term()).
register_service(Svc) when is_list(Svc) ->
    Name = sc_util:req_val(name, Svc),
    sc_config:set({service, Name}, Svc).

%%--------------------------------------------------------------------
%% @doc Unregister a service in the service configuration registry.
%% @see start_service/1
%% @end
%%--------------------------------------------------------------------
-spec unregister_service(ServiceName::atom()) -> ok.
unregister_service(Name) when is_atom(Name) ->
    ok = sc_config:delete({service, Name}).

%%--------------------------------------------------------------------
%% @doc Get service configuration
%% @see start_service/1
%% @end
%%--------------------------------------------------------------------
-type std_proplist() :: sc_types:proplist(atom(), term()).
-spec get_service_config(Service::term()) ->
    {ok, std_proplist()} | {error, term()}.
get_service_config(Service) ->
    case sc_config:get({service, Service}) of
        SvcConfig when is_list(SvcConfig) ->
            {ok, SvcConfig};
        undefined ->
            {error, {unregistered_service, Service}}
    end.

