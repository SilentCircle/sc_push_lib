%%%-------------------------------------------------------------------
%%% @author Edwin Fine
%%% @copyright (C) 2012,2013 Silent Circle LLC
%%% @doc
%%%
%%% @end
%%% Created : 2013-01-02 15:28:58.189830
%%%-------------------------------------------------------------------
-module(sc_push_lib).

-export([
        register_service/1,
        unregister_service/1,
        get_service_config/1
    ]).

%%--------------------------------------------------------------------
%% @doc Register a service in the service configuration registry.
%% @see start_service/1
%% @end
%%--------------------------------------------------------------------
-spec register_service(sc_types:proplist(atom(), term())) -> ok.
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

