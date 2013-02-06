-module(sc_push_reg_api).

-export([
    init/0,
    register_id/1,
    reregister_id/2,
    register_ids/1,
    deregister_id/1,
    deregister_ids/1,
    all_registration_info/0,
    get_registration_info/1,
    get_registration_info_by_id/1,
    get_registration_info_by_tag/1,
    make_sc_push_props/5,
    make_id/2,
    is_valid_push_reg/1
    ]).

-export_type([
        reg_id_key/0
        ]).

-include("sc_push_lib.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

-define(NS_SC_PUSH, "http://silentcircle.com/protocol/push").

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-opaque reg_id_key() :: {atom(), binary()}.
-type atom_or_str() :: atom() | string().
-type bin_or_str() :: binary() | string().
-type atomable() :: atom() | string() | binary().
-type binable() :: atom() | binary() | integer() | iolist().
-type reg_id_keys() :: [reg_id_key()].

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
        id = {undefined, <<>>} :: reg_id_key(), % {service, token (APNS token, Android reg ID)}
        tag = <<>> :: binary(), % User identification tag, e.g. <<"user@server">>
        app_id = <<>> :: binary(), % iOS AppBundleID, Android package
        dist = <<>> :: binary(), % distribution <<>> is same as <<"prod">>, or <<"dev">>
        last_updated = now()
    }).

-type push_reg_list() :: list(#sc_pshrg{}).

%%====================================================================
%% API
%%====================================================================
%% @doc Initialize API.
-spec init() -> ok.
init() ->
    create_tables([node()]),
    ok.

%% @doc Get registration info of all registered IDs. Note
%% that in future, this may be limited to the first 100
%% IDs found. It may also be supplemented by an API that
%% supports getting the information in batches.
-spec all_registration_info() -> [sc_types:reg_proplist()].
all_registration_info() ->
    [sc_pshrg_to_props(R) || R <- all_reg()].

%% @doc Register an identity for receiving push notifications
%% from a supported push service.
-spec register_id(sc_types:reg_proplist()) -> sc_types:reg_result().
register_id([{_, _}|_] = Props) ->
    register_ids([Props]).

%% @doc Reregister a previously-registered identity, substituting a new token
%% for the specified push service.
-spec reregister_id(reg_id_key(), binary()) -> ok.
reregister_id(OldId, <<NewToken/binary>>) ->
    reregister_id_impl(OldId, NewToken).

%% @doc Register a list of identities that should receive push notifications.
-spec register_ids([sc_types:reg_proplist(), ...]) -> ok | {error, term()}.
register_ids([[{_, _}|_]|_] = ListOfProplists) ->
    try
        save_push_regs([make_sc_pshrg(PL) || PL <- ListOfProplists])
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister an identity using a key returned by make_id/2.
-spec deregister_id(reg_id_key()) -> ok | {error, term()}.
deregister_id(ID) ->
    deregister_ids([ID]).

%% @doc Deregister a list of identities.
-spec deregister_ids(reg_id_keys()) -> ok | {error, term()}.
deregister_ids(IDs) when is_list(IDs) ->
    try
        CheckedIDs = check_ids(IDs),
        delete_push_regs(CheckedIDs)
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Get the registration information for a tag.
-spec get_registration_info(bin_or_str()) -> [sc_types:reg_proplist()] | notfound.
get_registration_info(Tag) ->
    get_registration_info_by_tag(sc_util:to_bin(Tag)).

%% @doc Get the registration information using a key returned by make_id/2.
-spec get_registration_info_by_id(reg_id_key()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info_by_id(ID) ->
    case lookup_reg_id(ID) of
        [#sc_pshrg{} = Reg] ->
            sc_pshrg_to_props(Reg);
        [] ->
            notfound
    end.

-spec get_registration_info_by_tag(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(Tag) ->
    case lookup_reg_tag(Tag) of
        [#sc_pshrg{}|_] = Regs ->
            [sc_pshrg_to_props(Reg) || Reg <- Regs];
        [] ->
            notfound
    end.

%% @doc Create a registration proplist required by other functions
%% in this API.
-spec make_sc_push_props(atomable(), binable(), binable(),
                         binable(), binable())
    -> [{'app_id', binary()} |
        {'dist', binary()} |
        {'service', atom()} |
        {'tag', binary()} |
        {'token', binary()}].

make_sc_push_props(Service, Token, Tag, AppId, Dist) ->
    [
        {service, sc_util:to_atom(Service)},
        {token, sc_util:to_bin(Token)},
        {tag, sc_util:to_bin(Tag)},
        {app_id, sc_util:to_bin(AppId)},
        {dist, sc_util:to_bin(Dist)}
    ].

%% @doc Create an opaque registration ID key for use with other functions
%% in this API.
-spec make_id(atom_or_str(), binable()) -> reg_id_key().
make_id(Service, Token) when is_atom(Service) ->
    {Service, sc_util:to_bin(Token)};
make_id(Service, Token) when is_list(Service) ->
    make_id(list_to_atom(Service), Token).

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

is_valid_push_reg(PL) ->
    try make_sc_pshrg(PL) of
        _ -> true
    catch _:_ -> false
    end.

sc_pshrg_to_props(#sc_pshrg{id = ID, tag = Tag, app_id = AppId, dist = Dist}) ->
    {Service, Token} = split_id(ID),
    make_sc_push_props(Service, Token, Tag, AppId, Dist).

-spec split_id(reg_id_key()) -> {atom(), binary()}.
split_id(ID) ->
    ID.

-spec check_id(reg_id_key()) -> reg_id_key().
check_id(ID) ->
    case split_id(ID) of
       {S, T} when is_atom(S), is_binary(T) ->
           ID;
       _ ->
           throw({bad_reg_id, ID})
    end.

-spec check_ids(reg_id_keys()) -> reg_id_keys().
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

-spec all_reg() -> push_reg_list().
all_reg() ->
    mnesia:dirty_select(sc_pshrg, ets:fun2ms(fun(R) -> R end)).

-spec lookup_reg_id(reg_id_key()) -> push_reg_list().
lookup_reg_id(ID) ->
    mnesia:dirty_read(sc_pshrg, ID).

-spec lookup_reg_tag(binary()) -> push_reg_list().
lookup_reg_tag(Tag) when is_binary(Tag) ->
    mnesia:dirty_index_read(sc_pshrg, Tag, #sc_pshrg.tag).

-spec save_push_regs(push_reg_list()) -> ok | {error, term()}.
save_push_regs(PushRegs) ->
    do_txn(save_push_regs_txn(), [PushRegs]).

-spec delete_push_regs(reg_id_keys()) -> ok | {error, term()}.
delete_push_regs(IDs) ->
    dirty_txn(delete_push_regs_txn(), [IDs]).

-spec reregister_id_impl(reg_id_key(), binary()) -> ok.
reregister_id_impl(OldId, NewToken) ->
    do_txn(reregister_id_txn(), [OldId, NewToken]).

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

-spec reregister_id_txn() -> fun((reg_id_key(), binary()) -> ok).
reregister_id_txn() ->
    fun(OldId, NewToken) ->
            case mnesia:read(sc_pshrg, OldId) of
                [#sc_pshrg{id = {Svc, _Tok} = Key} = R] ->
                    ok = mnesia:delete({sc_pshrg, Key}), 
                    ok = mnesia:write(R#sc_pshrg{id = make_id(Svc, NewToken)});
                [] -> % Does not exist, so that's fine
                    ok
            end
    end.

-spec do_txn(fun(), list()) -> Result::term().
do_txn(Txn, Args) ->
    {atomic, Result} = mnesia:transaction(Txn, Args),
    Result.

dirty_txn(Txn, Args) ->
    mnesia:async_dirty(Txn, Args).

