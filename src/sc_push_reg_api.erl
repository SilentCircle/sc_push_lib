-module(sc_push_reg_api).

-export([
        init/0,
        register_id/1,
        register_ids/1,
        deregister_id/1,
        deregister_ids/1,
        get_registration_info/1,
        make_sc_push_props/5,
        make_id/2
     ]).

-include("sc_push_lib.hrl").

-define(NS_SC_PUSH, "http://silentcircle.com/protocol/push").

%%--------------------------------------------------------------------
%% Records
%%--------------------------------------------------------------------
% Keying by JID with resource was not such a good idea. If resource changes,
% such as server-generated resources, this will simply not work or will grow
% without bound. Create a unique ID based on {service, token}, and use binary
% tags instead of XMPP-specific identifiers like {User, Server}.  We rely on
% the feedback services to tell us when a token is no longer valid so that we
% can delete the obsolete token record.
%
% id is composed of {service :: atom(), token :: binary()}.  service is the
% push service, currently only apns (Apple) and gcm (Google) token is the push
% token as sent to the push service.
%
-record(sc_pshrg, {
        id = {undefined, <<>>} :: tuple(), % {service, token (APNS token, Android reg ID)}
        tag = <<>> :: binary(), % User identification tag, e.g. <<"user@server">>
        app_id = <<>> :: binary(), % iOS AppBundleID, Android package
        dist = <<>> :: binary(), % distribution <<>> is same as <<"prod">>, or <<"dev">>
        last_updated = now()
    }).

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-type push_reg_list() :: list(#sc_pshrg{}).


%%====================================================================
%% API
%%====================================================================
init() ->
    create_tables([node()]),
    ok.

-spec register_id(sc_types:reg_proplist()) -> sc_types:reg_result().
register_id([{_, _}|_] = Props) ->
    register_ids([Props]).

%% Returns list of results in same order as requests.
%% Results = [Result]
%% Result = ok | {error, Reason}
-spec register_ids([sc_types:reg_proplist(), ...]) -> [sc_types:reg_result(), ...].
register_ids([[{_, _}|_]|_] = ListOfProplists) ->
    try
        save_push_regs([make_sc_pshrg(PL) || PL <- ListOfProplists])
    catch
        _:Reason ->
            {error, Reason}
    end.

-spec deregister_id(sc_types:dereg_id()) -> sc_types:reg_result().
deregister_id({_, _} = ID) ->
    deregister_ids([ID]).

%% Result = ok | {error, Reason}
-spec deregister_ids([sc_types:reg_proplist(), ...]) ->
      ok | {error, term()}.
deregister_ids(IDs) when is_list(IDs) ->
    try
        CheckedIDs = check_ids(IDs),
        delete_push_regs(CheckedIDs)
    catch
        _:Reason ->
            {error, Reason}
    end.

get_registration_info(Tag) ->
    case lookup_reg(sc_util:to_bin(Tag)) of
        [#sc_pshrg{}|_] = Regs ->
            [sc_pshrg_to_props(Reg) || Reg <- Regs];
        [] ->
            notfound
    end.

make_sc_push_props(Service, Token, Tag, AppId, Dist) ->
    [
        {service, Service},
        {token, Token},
        {tag, Tag},
        {app_id, AppId},
        {dist, Dist}
    ].

%%====================================================================
%% Internal functions
%%====================================================================
make_sc_pshrg([_|_] = Props)  ->
    SvcAsStr = sc_util:to_list(sc_util:val(service, Props, "apns")),
    Service = sc_util:to_atom(sc_util:req_s(SvcAsStr)),

    Token = sc_util:req_val(token, Props),
    Tag = sc_util:val(tag, Props, ""),
    AppId = sc_util:req_val(app_id, Props),
    Dist = sc_util:val(dist, Props, ""),

    make_sc_pshrg(Service, Token, Tag, AppId, Dist).

make_sc_pshrg(Service, Token, Tag, AppId, Dist) when is_atom(Service) ->
    #sc_pshrg{
        id = make_id(Service, Token),
        tag = sc_util:to_bin(Tag),
        app_id = sc_util:to_bin(AppId),
        dist = sc_util:to_bin(Dist)
    }.

sc_pshrg_to_props(#sc_pshrg{id = ID, tag = Tag, app_id = AppId, dist = Dist}) ->
    {Service, Token} = split_id(ID),
    make_sc_push_props(Service, Token, Tag, AppId, Dist).

%% Yes, it's an identity function. Maybe it won't be one day.
split_id({_Service, _Token} = Id) ->
    Id.

make_id(Service, Token) when is_atom(Service) ->
    {Service, sc_util:to_bin(Token)};
make_id(Service, Token) when is_list(Service) ->
    make_id(list_to_atom(Service), Token).

check_id({Service, Token}) when is_atom(Service), is_binary(Token) ->
    make_id(Service, Token);
check_id(Other) ->
    throw({bad_reg_id, Other}).

check_ids(IDs) when is_list(IDs) ->
    [check_id(ID) || ID <- IDs].

%%--------------------------------------------------------------------
%% Database functions
%%--------------------------------------------------------------------
create_tables(Nodes) ->
    Res = mnesia:create_table(sc_pshrg,
        [{disc_copies, Nodes},
         {type, set},
         {index, [#sc_pshrg.tag]},
         {attributes, record_info(fields, sc_pshrg)}]
    ),
    
    case Res of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        _ ->
            throw({create_table_error, Res})
    end.

-spec lookup_reg(binary()) -> push_reg_list().
lookup_reg(Tag) ->
    mnesia:dirty_index_read(sc_pshrg, Tag, #sc_pshrg.tag).

-spec save_push_regs(push_reg_list()) -> ok | {error, term()}.
save_push_regs(PushRegs) ->
    do_txn(save_push_regs_txn(), [PushRegs]).

-spec delete_push_regs(list({Service::atom(), Token::binary()})) ->
    ok | {error, term()}.
delete_push_regs(IDs) ->
    dirty_txn(delete_push_regs_txn(), [IDs]).

-spec save_push_regs_txn() -> fun((push_reg_list()) -> ok).
save_push_regs_txn() ->
    fun(PushRegs) ->
            [mnesia:write(R) || R <- PushRegs],
            ok
    end.

-spec delete_push_regs_txn() -> fun((push_reg_list()) -> ok).
delete_push_regs_txn() ->
    fun(IDs) ->
            [mnesia:delete({sc_pshrg, ID}) || ID <- IDs],
            ok
    end.

-spec do_txn(fun(), list()) -> Result::term().
do_txn(Txn, Args) ->
    {atomic, Result} = mnesia:transaction(Txn, Args),
    Result.

dirty_txn(Txn, Args) ->
    mnesia:async_dirty(Txn, Args).

