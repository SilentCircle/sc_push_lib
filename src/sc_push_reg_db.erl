-module(sc_push_reg_db).

-export([
        create_tables/1,
        make_id/1,
        make_svc_tok/2,
        all_registration_info/0,
        all_reg/0,
        get_registration_info_by_id/1,
        get_registration_info_by_tag/1,
        get_registration_info_by_svc_tok/1,
        save_push_regs/1,
        delete_push_regs_by_ids/1,
        delete_push_regs_by_tags/1,
        delete_push_regs_by_svc_toks/1,
        reregister_ids/1,
        is_valid_push_reg/1,
        check_ids/1,
        check_id/1,
        make_sc_push_props/8
    ]).

-export_type([
        reg_id_key/0,
        svc_tok_key/0
        ]).

-include("sc_push_lib.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-type reg_id_key() :: binary().
-type svc_tok_key() :: {atom(), binary()}.
-type atom_or_str() :: atom() | string().
-type atomable() :: atom() | string() | binary().
-type binable() :: atom() | binary() | integer() | iolist().
-type reg_id_keys() :: [reg_id_key()].

%%--------------------------------------------------------------------
%% Records
%%--------------------------------------------------------------------
% id is a globally unique identifier that is used to identify
% an app/device/user combination anonymously.
-record(sc_pshrg, {
        id = <<>> :: reg_id_key(), % device_id
        svc_tok = {undefined, <<>>} :: svc_tok_key(),
        tag = <<>> :: binary(), % User identification tag, e.g. <<"user@server">>
        app_id = <<>> :: binary(), % iOS AppBundleID, Android package
        dist = <<>> :: binary(), % distribution <<>> is same as <<"prod">>, or <<"dev">>
        version = 0 :: non_neg_integer(), % unsplit support
        modified = {0, 0, 0} :: erlang:timestamp()    % unsplit support
    }).

-type push_reg_list() :: list(#sc_pshrg{}).

%%====================================================================
%% API
%%====================================================================
-spec all_registration_info() -> [sc_types:reg_proplist()].
all_registration_info() ->
    [sc_pshrg_to_props(R) || R <- all_reg()].

%% @doc Get the registration information using a key returned by make_id.
-spec get_registration_info_by_id(reg_id_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_id(ID) ->
    get_registration_info_impl(ID, fun lookup_reg_id/1).

-spec get_registration_info_by_tag(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(Tag) ->
    get_registration_info_impl(Tag, fun lookup_reg_tag/1).

-spec get_registration_info_by_svc_tok(svc_tok_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_svc_tok({_Service, _Token} = SvcTok) ->
    get_registration_info_impl(SvcTok, fun lookup_svc_tok/1).

%% @doc Create a registration proplist required by other functions
%% in this API.
-spec make_sc_push_props(atomable(), binable(), binable(),
                         binable(), binable(), binable(),
                         non_neg_integer(), erlang:timestamp())
    -> [{'app_id', binary()} |
        {'dist', binary()} |
        {'service', atom()} |
        {'device_id', binary()} |
        {'tag', binary()} |
        {'modified', tuple()} |
        {'version', non_neg_integer()} |
        {'token', binary()}].

make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist, Vsn, Mod) ->
    [
        {device_id, sc_util:to_bin(DeviceId)},
        {service, sc_util:to_atom(Service)},
        {token, sc_util:to_bin(Token)},
        {tag, sc_util:to_bin(Tag)},
        {app_id, sc_util:to_bin(AppId)},
        {dist, sc_util:to_bin(Dist)},
        {version, Vsn},
        {modified, Mod}
    ].

%% @doc Convert to an opaque registration ID key.
-spec make_id(binable()) -> reg_id_key().
make_id(Id) ->
    case sc_util:to_bin(Id) of
        <<>> ->
            throw({invalid_id, Id});
        B ->
            B
    end.

%% @doc Convert to an opaque service-token key.
-spec make_svc_tok(atom_or_str(), binable()) -> svc_tok_key().
make_svc_tok(Service, Token) when is_atom(Service) ->
    {Service, sc_util:to_bin(Token)};
make_svc_tok(Service, Token) when is_list(Service) ->
    make_svc_tok(list_to_atom(Service), Token).

%%====================================================================
%% Internal functions
%%====================================================================
make_sc_pshrg([_|_] = Props)  ->
    ServiceS = sc_util:to_list(sc_util:val(service, Props, "apns")),
    Service = sc_util:to_atom(sc_util:req_s(ServiceS)),
    Token = sc_util:req_val(token, Props),
    DeviceId = sc_util:req_val(device_id, Props),
    Tag = sc_util:val(tag, Props, ""),
    AppId = sc_util:req_val(app_id, Props),
    Dist = sc_util:val(dist, Props, ""),
    make_sc_pshrg(Service, Token, DeviceId, Tag, AppId, Dist).

-spec make_sc_pshrg(atom_or_str(), binable(), binable(),
                    binable(), binable(), binable()) -> #sc_pshrg{}.
make_sc_pshrg(Service, Token, DeviceId, Tag, AppId, Dist) ->
    make_sc_pshrg(Service, Token, DeviceId, Tag, AppId, Dist, 0,
                  os:timestamp()).

-spec make_sc_pshrg(atom_or_str(), binable(), binable(),
                    binable(), binable(), binable(), non_neg_integer(),
                    erlang:timestamp()) -> #sc_pshrg{}.
make_sc_pshrg(Service, Token, DeviceId, Tag, AppId, Dist, Version, Modified) ->
    #sc_pshrg{
        id = make_id(DeviceId),
        svc_tok = make_svc_tok(Service, Token),
        tag = sc_util:to_bin(Tag),
        app_id = sc_util:to_bin(AppId),
        dist = sc_util:to_bin(Dist),
        version = Version,
        modified = Modified
    }.

is_valid_push_reg(PL) ->
    try make_sc_pshrg(PL) of
        _ -> true
    catch _:_ -> false
    end.

sc_pshrg_to_props(#sc_pshrg{id = ID,
                            svc_tok = SvcToken,
                            tag = Tag,
                            app_id = AppId,
                            dist = Dist,
                            version = Vsn,
                            modified = Modified}) ->
    {Service, Token} = SvcToken,
    make_sc_push_props(Service, Token, reg_id_key_to_bin(ID), Tag,
                       AppId, Dist, Vsn, Modified).

-spec check_id(reg_id_key()) -> reg_id_key().
check_id(ID) ->
    case ID of
       <<_>> when byte_size(ID) > 0 ->
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
            [
                {disc_copies, Nodes},
                {type, set},
                {index, [#sc_pshrg.tag, #sc_pshrg.svc_tok]},
                {attributes, record_info(fields, sc_pshrg)},
                {user_properties,
                    [{unsplit_method, {unsplit_lib, last_modified, []}}]
                }
            ]
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
            Vers = 1, % Record version
            ModTs = os:timestamp(),
            % Token is used as default ID when converting from old-style records
            Xform = fun({sc_pshrg, {Svc, Tok}, Tag, AppId, Dist, _Time}) ->
                    ID = Tok,
                    make_sc_pshrg(Svc, Tok, ID, fix_tag(Tag), AppId, Dist, Vers, ModTs)
            end,

            % Transform table (will transform all replicas of the table
            % on other nodes, too, and if they are running the old code,
            % the process will crash when the table is upgraded.
            NewAttrs = record_info(fields, sc_pshrg),
            delete_all_table_indexes(sc_pshrg),
            {atomic, ok} = mnesia:transform_table(sc_pshrg, Xform, NewAttrs),
            add_table_indexes(sc_pshrg, [tag, svc_tok]),
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
    do_txn(fun() ->
                mnesia:select(sc_pshrg, ets:fun2ms(fun(R) -> R end))
        end).

-spec lookup_reg_id(reg_id_key()) -> push_reg_list().
lookup_reg_id(ID) ->
    do_txn(fun() -> mnesia:read(sc_pshrg, ID) end).

-spec lookup_reg_tag(binary()) -> push_reg_list().
lookup_reg_tag(Tag) when is_binary(Tag) ->
    do_txn(fun() ->
                mnesia:index_read(sc_pshrg, Tag, #sc_pshrg.tag)
        end).

-spec lookup_svc_tok(svc_tok_key()) -> push_reg_list().
lookup_svc_tok({Service, Token} = SvcTok) when is_atom(Service), is_binary(Token) ->
    do_txn(fun() ->
                mnesia:index_read(sc_pshrg, SvcTok, #sc_pshrg.svc_tok)
        end).

-spec save_push_regs([sc_types:reg_proplist(), ...]) -> ok | {error, term()}.
save_push_regs(ListOfProplists) ->
    Regs = [make_sc_pshrg(PL) || PL <- ListOfProplists],
    do_txn(save_push_regs_txn(), [Regs]).

-spec delete_push_regs_by_ids(reg_id_keys()) -> ok | {error, term()}.
delete_push_regs_by_ids(IDs) ->
    do_txn(delete_push_regs_txn(), [IDs]).

-spec delete_push_regs_by_svc_toks([svc_tok_key()]) -> ok | {error, term()}.
delete_push_regs_by_svc_toks(SvcToks) when is_list(SvcToks) ->
    do_txn(delete_push_regs_by_svc_tok_txn(), [SvcToks]).

-spec delete_push_regs_by_tags([binary()]) -> ok | {error, term()}.
delete_push_regs_by_tags(Tags) when is_list(Tags) ->
    do_txn(delete_push_regs_by_tag_txn(), [Tags]).

-spec reregister_ids([{reg_id_key(), binary()}]) -> ok.
reregister_ids(IDToks) when is_list(IDToks) ->
    do_txn(reregister_ids_txn(), [IDToks]).

-spec save_push_regs_txn() -> fun((push_reg_list()) -> ok).
save_push_regs_txn() ->
    fun(PushRegs) ->
            [write_rec(R) || R <- PushRegs],
            ok
    end.

-spec delete_push_regs_txn() -> fun(([binary()]) -> ok).
delete_push_regs_txn() ->
    fun(IDs) ->
            [mnesia:delete({sc_pshrg, ID}) || ID <- IDs],
            ok
    end.

-spec delete_push_regs_by_tag_txn() -> fun(([binary()]) -> ok).
delete_push_regs_by_tag_txn() ->
    delete_push_regs_by_index_txn(#sc_pshrg.tag).

-spec delete_push_regs_by_svc_tok_txn() -> fun(([svc_tok_key()]) -> ok).
delete_push_regs_by_svc_tok_txn() ->
    delete_push_regs_by_index_txn(#sc_pshrg.svc_tok).

-spec delete_push_regs_by_index_txn(non_neg_integer()) -> fun(([term()]) -> ok).
delete_push_regs_by_index_txn(Index) ->
    fun(Keys) ->
            [delete_push_reg_by_index(Key, Index) || Key <- Keys],
            ok
    end.

%% MUST be called in txn
-spec delete_push_reg_by_index(term(), non_neg_integer()) -> ok.
delete_push_reg_by_index(Key, Index) ->
    case mnesia:index_read(sc_pshrg, Key, Index) of
        [] ->
            ok;
        Recs ->
            [mnesia:delete({sc_pshrg, R#sc_pshrg.id}) || R <- Recs]
    end,
    ok.

-spec reregister_ids_txn() -> fun(([{reg_id_key(), binary()}]) -> ok).
reregister_ids_txn() ->
    fun(IDToks) ->
            [reregister_one_id(ID, NewTok) || {ID, NewTok} <- IDToks],
            ok
    end.

%% MUST be called in a transaction
reregister_one_id(ID, NewTok) ->
    case mnesia:read(sc_pshrg, ID) of
        [#sc_pshrg{svc_tok = {Svc, _Tok}} = R] ->
            R1 = R#sc_pshrg{svc_tok = make_svc_tok(Svc, NewTok)},
            write_rec(R1);
        [] -> % Does not exist, so that's fine
            ok
    end.

%% MUST be called in a transaction.
-compile({inline, [{write_rec, 1}]}).
write_rec(#sc_pshrg{} = R) ->
    ok = mnesia:write(inc(R)).

-compile({inline, [{inc, 1}]}).
inc(#sc_pshrg{version = V} = R) ->
    R#sc_pshrg{modified = os:timestamp(), version = V + 1}.

%% NOTE: Chose sync_transaction here because cluster may
%% extend across data centers, and
%% - If 2nd phase commit fails and
%% - Network to DC is down, and
%% - Async transaction is used
%% Then this transaction may quietly be reversed when connectivity is restored,
%% even after it's told the caller it succeeded.
-compile({inline, [{do_txn, 2}]}).
-spec do_txn(fun(), list()) -> Result::term().
do_txn(Txn, Args) ->
    {atomic, Result} = mnesia:sync_transaction(Txn, Args),
    Result.

-compile({inline, [{do_txn, 1}]}).
-spec do_txn(fun()) -> Result::term().
do_txn(Txn) ->
    do_txn(Txn, []).

%% MUST be in transaction
get_registration_info_impl(Key, DBLookup) when is_function(DBLookup, 1) ->
    case DBLookup(Key) of
        [#sc_pshrg{}|_] = Regs ->
            [sc_pshrg_to_props(Reg) || Reg <- Regs];
        [] ->
            notfound
    end.

-compile({inline, [{reg_id_key_to_bin, 1}]}).
-spec reg_id_key_to_bin(reg_id_key()) -> binary().
reg_id_key_to_bin(ID) ->
    ID.

