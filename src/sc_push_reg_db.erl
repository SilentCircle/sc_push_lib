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

-module(sc_push_reg_db).

-export([
        all_reg/0,
        all_registration_info/0,
        check_id/1,
        check_ids/1,
        create_tables/1,
        delete_push_regs_by_device_ids/1,
        delete_push_regs_by_ids/1,
        delete_push_regs_by_svc_toks/1,
        delete_push_regs_by_tags/1,
        get_registration_info_by_device_id/1,
        get_registration_info_by_id/1,
        get_registration_info_by_svc_tok/1,
        get_registration_info_by_tag/1,
        is_valid_push_reg/1,
        init/1,
        make_id/2,
        make_sc_push_props/8,
        make_svc_tok/2,
        reregister_ids/1,
        reregister_svc_toks/1,
        save_push_regs/1
    ]).

-export_type([
        reg_id_key/0,
        svc_tok_key/0
        ]).

-include("sc_push_lib.hrl").
-include_lib("stdlib/include/ms_transform.hrl").

%% FIXME: May want to choose sync_transaction because cluster may
%% extend across data centers, and
%% - If 2nd phase commit fails and
%% - Network to DC is down, and
%% - Async transaction is used
%% Then this transaction may quietly be reversed when connectivity is restored,
%% even after it's told the caller it succeeded.
%% OTOH, it's much much slower. So we'll leave it as a compile-time option.

-ifdef(SC_MNESIA_SYNC_TRANSACTIONS).
-define(TXN2(Txn, Args), mnesia:sync_transaction(Txn, Args)).
-else.
-define(TXN2(Txn, Args), mnesia:transaction(Txn, Args)).
-endif.

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-type reg_id_key() :: {binary(), binary()}.
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
        id = {<<>>, <<>>} :: reg_id_key(),
        device_id = <<>> :: binary(),
        tag = <<>> :: binary(), % User identification tag, e.g. <<"user@server">>
        svc_tok = {undefined, <<>>} :: svc_tok_key(),
        app_id = <<>> :: binary(), % iOS AppBundleID, Android package
        dist = <<>> :: binary(), % distribution <<>> is same as <<"prod">>, or <<"dev">>
        version = 0 :: non_neg_integer(),
        modified = {0, 0, 0} :: erlang:timestamp()
    }).

-type push_reg_list() :: list(#sc_pshrg{}).

%%====================================================================
%% API
%%====================================================================
%% @doc Return a list of property lists of all registrations.
%% @deprecated For debug only
-spec all_registration_info() -> [sc_types:reg_proplist()].
all_registration_info() ->
    [sc_pshrg_to_props(R) || R <- all_reg()].

%% @doc Return a list of all push registration records.
%% @deprecated For debug only.
-spec all_reg() -> push_reg_list().
all_reg() ->
    do_txn(fun() ->
                mnesia:select(sc_pshrg, ets:fun2ms(fun(R) -> R end))
        end).

%% @doc Check registration id key.
-spec check_id(reg_id_key()) -> reg_id_key().
check_id(ID) ->
    case ID of
        {<<_, _/binary>>, <<_, _/binary>>} ->
           ID;
       _ ->
           throw({bad_reg_id, ID})
    end.

%% @doc Check multiple registration id keys.
-spec check_ids(reg_id_keys()) -> reg_id_keys().
check_ids(IDs) when is_list(IDs) ->
    [check_id(ID) || ID <- IDs].

init(Nodes) ->
    case application:get_env(mnesia, dir) of
        {ok, Dir} ->
            lager:info("Mnesia dir: ~s", [Dir]),
            ok = filelib:ensure_dir(Dir),
            create_tables(Nodes);
        _Error ->
            erlang:error("mnesia dir needs to be defined in env")
    end.

create_tables(Nodes) ->
    Defs = [
        {sc_pshrg,
            [
                {disc_copies, Nodes},
                {type, set},
                {index, [#sc_pshrg.device_id, #sc_pshrg.tag, #sc_pshrg.svc_tok]},
                {attributes, record_info(fields, sc_pshrg)}
            ]
        }
    ],

    _ = [create_table(Tab, Attrs) || {Tab, Attrs} <- Defs],
    upgrade_tables().

%% @doc Delete push registrations by device ids
-spec delete_push_regs_by_device_ids([binary()]) -> ok | {error, term()}.
delete_push_regs_by_device_ids(DeviceIDs) when is_list(DeviceIDs) ->
    do_txn(delete_push_regs_by_device_id_txn(), [DeviceIDs]).

%% @doc Delete push registrations by internal registration id.
-spec delete_push_regs_by_ids(reg_id_keys()) -> ok | {error, term()}.
delete_push_regs_by_ids(IDs) ->
    do_txn(delete_push_regs_txn(), [IDs]).

%% @doc Delete push registrations by service-token.
-spec delete_push_regs_by_svc_toks([svc_tok_key()]) -> ok | {error, term()}.
delete_push_regs_by_svc_toks(SvcToks) when is_list(SvcToks) ->
    do_txn(delete_push_regs_by_svc_tok_txn(), [SvcToks]).

%% @doc Delete push registrations by tags.
-spec delete_push_regs_by_tags([binary()]) -> ok | {error, term()}.
delete_push_regs_by_tags(Tags) when is_list(Tags) ->
    do_txn(delete_push_regs_by_tag_txn(), [Tags]).

%% @doc Get registration information by device id.
-spec get_registration_info_by_device_id(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_device_id(DeviceID) ->
    get_registration_info_impl(DeviceID, fun lookup_reg_device_id/1).

%% @doc Get registration information by unique id.
%% @see make_id/2
-spec get_registration_info_by_id(reg_id_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_id(ID) ->
    get_registration_info_impl(ID, fun lookup_reg_id/1).

%% @doc Get registration information by service-token.
%% @see make_svc_tok/2
-spec get_registration_info_by_svc_tok(svc_tok_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_svc_tok({_Service, _Token} = SvcTok) ->
    get_registration_info_impl(SvcTok, fun lookup_svc_tok/1).

%% @doc Get registration information by tag.
-spec get_registration_info_by_tag(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(Tag) ->
    get_registration_info_impl(Tag, fun lookup_reg_tag/1).

%% @doc Is push registration proplist valid?
-spec is_valid_push_reg(sc_types:proplist(atom(), term())) -> boolean().
is_valid_push_reg(PL) ->
    try make_sc_pshrg(PL) of
        _ -> true
    catch _:_ -> false
    end.

%% @doc Convert to an opaque registration ID key.
-spec make_id(binable(), binable()) -> reg_id_key().
make_id(Id, Tag) ->
    case {sc_util:to_bin(Id), sc_util:to_bin(Tag)} of
        {<<_,_/binary>>, <<_,_/binary>>} = Key ->
            Key;
        _IdTag ->
            throw({invalid_id_or_tag, {Id, Tag}})
    end.

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

%% @doc Convert to an opaque service-token key.
-spec make_svc_tok(atom_or_str(), binable()) -> svc_tok_key().
make_svc_tok(Service, Token) when is_atom(Service) ->
    {Service, sc_util:to_bin(Token)};
make_svc_tok(Service, Token) when is_list(Service) ->
    make_svc_tok(list_to_atom(Service), Token).

%% @doc Save a list of push registrations.
-spec save_push_regs([sc_types:reg_proplist(), ...]) -> ok | {error, term()}.
save_push_regs(ListOfProplists) ->
    Regs = [make_sc_pshrg(PL) || PL <- ListOfProplists],
    do_txn(save_push_regs_txn(), [Regs]).

%% @doc Re-register invalidated tokens
-spec reregister_ids([{reg_id_key(), binary()}]) -> ok.
reregister_ids(IDToks) when is_list(IDToks) ->
    do_txn(reregister_ids_txn(), [IDToks]).

%% @doc Re-register invalidated tokens by svc_tok
-spec reregister_svc_toks([{svc_tok_key(), binary()}]) -> ok.
reregister_svc_toks(SvcToks) when is_list(SvcToks) ->
    do_txn(reregister_svc_toks_txn(), [SvcToks]).

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
                  erlang:timestamp()).

-spec make_sc_pshrg(atom_or_str(), binable(), binable(),
                    binable(), binable(), binable(), non_neg_integer(),
                    erlang:timestamp()) -> #sc_pshrg{}.
make_sc_pshrg(Service, Token, DeviceId, Tag, AppId, Dist, Version, Modified) ->
    #sc_pshrg{
        id = make_id(DeviceId, Tag),
        device_id = DeviceId,
        tag = sc_util:to_bin(Tag),
        svc_tok = make_svc_tok(Service, Token),
        app_id = sc_util:to_bin(AppId),
        dist = sc_util:to_bin(Dist),
        version = Version,
        modified = Modified
    }.

sc_pshrg_to_props(#sc_pshrg{svc_tok = SvcToken,
                            tag = Tag,
                            device_id = DeviceID,
                            app_id = AppId,
                            dist = Dist,
                            version = Vsn,
                            modified = Modified}) ->
    {Service, Token} = SvcToken,
    make_sc_push_props(Service, Token, DeviceID, Tag,
                       AppId, Dist, Vsn, Modified).

%%--------------------------------------------------------------------
%% Database functions
%%--------------------------------------------------------------------
create_table(Tab, Attrs) ->
    Res = mnesia:create_table(Tab, Attrs),

    case Res of
        {atomic, ok} -> ok;
        {aborted, {already_exists, _}} -> ok;
        _ ->
            throw({create_table_error, Res})
    end.

upgrade_tables() ->
    ok.  % Nothing to do

-spec lookup_reg_id(reg_id_key()) -> push_reg_list().
lookup_reg_id(ID) ->
    do_txn(fun() -> mnesia:read(sc_pshrg, ID) end).

-spec lookup_reg_device_id(binary()) -> push_reg_list().
lookup_reg_device_id(DeviceID) when is_binary(DeviceID) ->
    do_txn(fun() ->
                mnesia:index_read(sc_pshrg, DeviceID, #sc_pshrg.device_id)
        end).

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

-spec save_push_regs_txn() -> fun((push_reg_list()) -> ok).
save_push_regs_txn() ->
    fun(PushRegs) ->
            [write_rec(R) || R <- PushRegs],
            ok
    end.

-spec delete_push_regs_txn() -> fun(([binary()]) -> ok).
delete_push_regs_txn() ->
    fun(IDs) ->
            _ = [mnesia:delete({sc_pshrg, ID}) || ID <- IDs],
            ok
    end.

-spec delete_push_regs_by_tag_txn() -> fun(([binary()]) -> ok).
delete_push_regs_by_tag_txn() ->
    delete_push_regs_by_index_txn(#sc_pshrg.tag).

-spec delete_push_regs_by_device_id_txn() -> fun(([binary()]) -> ok).
delete_push_regs_by_device_id_txn() ->
    delete_push_regs_by_index_txn(#sc_pshrg.device_id).

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
            _ = [mnesia:delete({sc_pshrg, R#sc_pshrg.id}) || R <- Recs],
            ok
    end.

-spec reregister_ids_txn() -> fun(([{reg_id_key(), binary()}]) -> ok).
reregister_ids_txn() ->
    fun(IDToks) ->
            [reregister_one_id(ID, NewTok) || {ID, NewTok} <- IDToks],
            ok
    end.

%% MUST be called in a transaction
reregister_one_id(ID, NewTok) ->
    case mnesia:read(sc_pshrg, ID, write) of
        [#sc_pshrg{svc_tok = {Svc, _}} = R] ->
            R1 = R#sc_pshrg{svc_tok = make_svc_tok(Svc, NewTok)},
            write_rec(R1);
        [] -> % Does not exist, so that's fine
            ok
    end.

-spec reregister_svc_toks_txn() -> fun(([{svc_tok_key(), binary()}]) -> ok).
reregister_svc_toks_txn() ->
    fun(SvcToks) ->
            [reregister_svc_toks(SvcTok, NewTok) || {SvcTok, NewTok} <- SvcToks],
            ok
    end.

%% MUST be called in a transaction
%% Legacy records: if token == device_id, change device_id as well.
reregister_svc_toks(OldSvcTok, NewTok) ->
    case mnesia:index_read(sc_pshrg, OldSvcTok, #sc_pshrg.svc_tok) of
        [] -> % Does not exist, so that's fine
            ok;
        [_|_] = Rs ->
            [ok = reregister_one_svc_tok(NewTok, R) || R <- Rs],
            ok
    end.

%% MUST be called in a transaction
reregister_one_svc_tok(NewTok, #sc_pshrg{svc_tok = {Svc, OldTok}} = R0) ->
    NewSvcTok = make_svc_tok(Svc, NewTok),
    % If old token same as old device ID, change device ID too
    % for legacy records
    R1 = case R0#sc_pshrg.id of
        {OldDeviceId, OldTag} when OldDeviceId =:= OldTok ->
            delete_rec(R0), % Delete old rec
            R0#sc_pshrg{id = make_id(NewTok, OldTag),
                        device_id = NewTok,
                        svc_tok = NewSvcTok};
        _ ->
            R0#sc_pshrg{svc_tok = NewSvcTok}
    end,
    write_rec(R1).

%% MUST be called in a transaction.
-compile({inline, [{write_rec, 1}]}).
write_rec(#sc_pshrg{} = R) ->
    ok = mnesia:write(inc(R)).

%% MUST be called in a transaction.
-compile({inline, [{delete_rec, 1}]}).
delete_rec(#sc_pshrg{} = R) ->
    ok = mnesia:delete_object(R).

-compile({inline, [{inc, 1}]}).
inc(#sc_pshrg{version = V} = R) ->
    R#sc_pshrg{modified = erlang:timestamp(), version = V + 1}.

-compile({inline, [{do_txn, 2}]}).
-spec do_txn(fun(), list()) -> Result::term().
do_txn(Txn, Args) ->
    {atomic, Result} = ?TXN2(Txn, Args),
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

