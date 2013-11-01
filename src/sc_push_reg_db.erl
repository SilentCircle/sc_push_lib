-module(sc_push_reg_db).

-export([
        make_id/2,
        all_registration_info/0,
        all_reg/0,
        get_registration_info_by_id/1,
        get_registration_info_by_device_id/1,
        get_registration_info_by_tag/1,
        save_push_regs/1,
        delete_push_regs/1,
        delete_push_regs_by_device_id/1,
        delete_push_regs_by_tag/1,
        reregister_id/2,
        reregister_by_device_id/2,
        is_valid_push_reg/1,
        check_ids/1,
        check_id/1,
        split_id/1,
        make_sc_push_props/6
    ]).

-export_type([
        reg_id_key/0
        ]).

-include("sc_push_lib.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-opaque reg_id_key() :: {atom(), binary()}.
-type atom_or_str() :: atom() | string().
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
% Note: It's better to add new fields at the end of the record because it doesn't
% mess with any indexes (which are correlated by field number).
-record(sc_pshrg, {
        id = {undefined, <<>>} :: reg_id_key(), % {service, token (APNS token, Android reg ID)}
        tag = <<>> :: binary(), % User identification tag, e.g. <<"user@server">>
        app_id = <<>> :: binary(), % iOS AppBundleID, Android package
        dist = <<>> :: binary(), % distribution <<>> is same as <<"prod">>, or <<"dev">>
        last_updated = now(),
        device_id = <<>> :: binary()
    }).

-type push_reg_list() :: list(#sc_pshrg{}).

%%====================================================================
%% API
%%====================================================================
-spec all_registration_info() -> [sc_types:reg_proplist()].
all_registration_info() ->
    [sc_pshrg_to_props(R) || R <- all_reg()].

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

%% @doc Get the registration information using device_id
-spec get_registration_info_by_device_id(binary()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info_by_device_id(ID) ->
    case lookup_device_id(ID) of
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
                         binable(), binable(), binable())
    -> [{'app_id', binary()} |
        {'dist', binary()} |
        {'service', atom()} |
        {'device_id', binary()} |
        {'tag', binary()} |
        {'token', binary()}].

make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist) ->
    [
        {service, sc_util:to_atom(Service)},
        {token, sc_util:to_bin(Token)},
        {device_id, sc_util:to_bin(DeviceId)},
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
    DeviceId = sc_util:val(device_id, Props, ""),
    AppId = sc_util:req_val(app_id, Props),
    Dist = sc_util:val(dist, Props, ""),

    make_sc_pshrg(Service, Token, DeviceId, Tag, AppId, Dist).

make_sc_pshrg(Service, Token, DeviceId, Tag, AppId, Dist) when is_atom(Service) ->
    #sc_pshrg{
        id = make_id(Service, Token),
        tag = sc_util:to_bin(Tag),
        device_id = sc_util:to_bin(DeviceId),
        app_id = sc_util:to_bin(AppId),
        dist = sc_util:to_bin(Dist)
    }.

is_valid_push_reg(PL) ->
    try make_sc_pshrg(PL) of
        _ -> true
    catch _:_ -> false
    end.

sc_pshrg_to_props(#sc_pshrg{id = ID,
                            device_id = DeviceId,
                            tag = Tag,
                            app_id = AppId,
                            dist = Dist}) ->
    {Service, Token} = split_id(ID),
    make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist).

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
    Defs = [
        {sc_pshrg, 
            [{disc_copies, Nodes},
                {type, set},
                {index, [#sc_pshrg.tag, #sc_pshrg.device_id]},
                {attributes, record_info(fields, sc_pshrg)}]
        }
    ],

    [create_table(Tab, Attrs) || {Tab, Attrs} <- Defs],
    upgrade_tables().

create_table(Tab, Attrs) ->
    Res = mnesia:create_table(Tab, Attrs),
    
    case Res of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        _ ->
            throw({create_table_error, Res})
    end.

upgrade_tables() ->
    upgrade_sc_pshrg().

upgrade_sc_pshrg() ->
    case mnesia:table_info(sc_pshrg, attributes) of
        [id, tag, app_id, dist, last_updated] -> % Old format
            ok = mnesia:wait_for_tables([sc_pshrg], 30000),
            Now = os:timestamp(),
            NullDeviceId = <<>>,
            Xform = fun({sc_pshrg, Id, Tag, AppId, Dist, _LastUpdated}) ->
                    {sc_pshrg, Id, fix_tag(Tag), AppId, Dist, Now, NullDeviceId}
            end,

            % Transform table (will transform all replicas of the table
            % on other nodes, too, and if they are running the old code,
            % the process will crash when the table is upgraded.
            NewAttrs = record_info(fields, sc_pshrg),
            delete_all_table_indexes(sc_pshrg),
            {atomic, ok} = mnesia:transform_table(sc_pshrg, Xform, NewAttrs),
            add_table_indexes(sc_pshrg, [tag, device_id]),
            ok;
        _ -> % Leave alone
            ok
    end.

%% Skip tags already with an "xmpp:" prefix
fix_tag(<<$x,$m,$p,$p,$:, _/binary>> = Tag) ->
    Tag;
%% Add prefix
fix_tag(<<Tag/binary>>) ->
    <<$x,$m,$p,$p,$:, Tag/binary>>.

delete_all_table_indexes(Tab) ->
    [{atomic, ok} = mnesia:del_table_index(Tab, N)
        || N <- mnesia:table_info(Tab, index)].

add_table_indexes(Tab, Attrs) ->
    [
        case mnesia:add_table_index(Tab, Attr) of
            {aborted,{already_exists, _, _}} ->
                ok;
            {atomic, ok} ->
                ok
        end || Attr <- Attrs
    ].

-spec all_reg() -> push_reg_list().
all_reg() ->
    mnesia:dirty_select(sc_pshrg, ets:fun2ms(fun(R) -> R end)).

-spec lookup_reg_id(reg_id_key()) -> push_reg_list().
lookup_reg_id(ID) ->
    mnesia:dirty_read(sc_pshrg, ID).

-spec lookup_device_id(binary()) -> push_reg_list().
lookup_device_id(ID) ->
    mnesia:dirty_index_read(sc_pshrg, ID, #sc_pshrg.device_id).

-spec lookup_reg_tag(binary()) -> push_reg_list().
lookup_reg_tag(Tag) when is_binary(Tag) ->
    mnesia:dirty_index_read(sc_pshrg, Tag, #sc_pshrg.tag).

-spec save_push_regs([sc_types:reg_proplist(), ...]) -> ok | {error, term()}.
save_push_regs(ListOfProplists) ->
    Regs = [make_sc_pshrg(PL) || PL <- ListOfProplists],
    do_txn(save_push_regs_txn(), [Regs]).

-spec delete_push_regs(reg_id_keys()) -> ok | {error, term()}.
delete_push_regs(IDs) ->
    do_txn(delete_push_regs_txn(), [IDs]).

-spec delete_push_regs_by_device_id([binary()]) -> ok | {error, term()}.
delete_push_regs_by_device_id(DevIDs) ->
    do_txn(delete_push_regs_by_device_id_txn(), [DevIDs]).

-spec delete_push_regs_by_tag(binary()) -> ok | {error, term()}.
delete_push_regs_by_tag(Tag) ->
    do_txn(delete_push_regs_by_tag_txn(), [Tag]).

-spec reregister_id(reg_id_key(), binary()) -> ok.
reregister_id(OldId, NewToken) ->
    do_txn(reregister_id_txn(), [OldId, NewToken]).

-spec reregister_by_device_id(binary(), binary()) -> ok.
reregister_by_device_id(DeviceId, NewToken) ->
    do_txn(reregister_by_device_id_txn(), [DeviceId, NewToken]).

-spec save_push_regs_txn() -> fun((push_reg_list()) -> ok).
save_push_regs_txn() ->
    fun(PushRegs) ->
            [write_rec(R) || R <- PushRegs],
            ok
    end.

-spec delete_push_regs_txn() -> fun((push_reg_list()) -> ok).
delete_push_regs_txn() ->
    fun(IDs) ->
            [mnesia:delete({sc_pshrg, ID}) || ID <- IDs],
            ok
    end.

-spec delete_push_regs_by_device_id_txn() -> fun(([binary()]) -> ok).
delete_push_regs_by_device_id_txn() ->
    % There must be at most one device ID per token, otherwise crash
    fun(DevIDs) ->
            [
                case mnesia:index_read(sc_pshrg, DevID, #sc_pshrg.device_id) of
                    [R] ->
                        mnesia:delete({sc_pshrg, R#sc_pshrg.id});
                    [] ->
                        ok
                end || DevID <- DevIDs, DevID =/= <<>>
            ],
            ok
    end.

-spec delete_push_regs_by_tag_txn() -> fun((binary()) -> ok).
delete_push_regs_by_tag_txn() ->
    fun(Tag) ->
            case mnesia:index_read(sc_pshrg, Tag, #sc_pshrg.tag) of
                [] ->
                    ok;
                Recs ->
                    [mnesia:delete({sc_pshrg, R#sc_pshrg.id}) || R <- Recs]
            end,
            ok
    end.

-spec reregister_id_txn() -> fun((reg_id_key(), binary()) -> ok).
reregister_id_txn() ->
    fun(OldId, NewToken) ->
            case mnesia:read(sc_pshrg, OldId) of
                [#sc_pshrg{id = {Svc, _Tok} = Key} = R] ->
                    ok = mnesia:delete({sc_pshrg, Key}), 
                    ok = write_rec(R#sc_pshrg{id = make_id(Svc, NewToken)});
                [] -> % Does not exist, so that's fine
                    ok
            end
    end.

%% MUST be called in a transaction.
%%
%% Allow duplicate device IDs that are empty binary, because this is the
%% default for old records before device IDs were added.
%%
%% Fail if there is already an equal device ID for a different
%% {service, token} primary key.
%% 
%% If the device ID and the key are both the same, or there is no equal device
%% ID, allow the record to be overwritten.
write_rec(#sc_pshrg{device_id = DevID} = R) ->
    mnesia:write(R),
    case DevID of
        <<>> ->
            ok;
        _ ->
            assert_unique_dev_id(R)
    end.

assert_unique_dev_id(#sc_pshrg{device_id = DevID} = R) ->
    case mnesia:index_read(sc_pshrg, DevID, #sc_pshrg.device_id) of
        [R] ->
            ok;
        [_|_] ->
            mnesia:abort({dup_device_id, DevID})
    end.

-spec reregister_by_device_id_txn() -> fun((binary(), binary()) -> ok).
reregister_by_device_id_txn() ->
    fun(DevID, NewToken) when DevID =/= <<>> ->
            case mnesia:index_read(sc_pshrg, DevID, #sc_pshrg.device_id) of
                [#sc_pshrg{id = {Svc, _Tok} = Key} = R] ->
                    ok = mnesia:delete({sc_pshrg, Key}), 
                    ok = write_rec(R#sc_pshrg{id = make_id(Svc, NewToken)});
                [] -> % Does not exist, so nothing to do
                    ok
            end;
        (DevID, _NewToken) ->
            mnesia:abort({invalid_dev_id, DevID})
    end.

-spec do_txn(fun(), list()) -> Result::term().
do_txn(Txn, Args) ->
    {atomic, Result} = mnesia:transaction(Txn, Args),
    Result.

dirty_txn(Txn, Args) ->
    mnesia:async_dirty(Txn, Args).

