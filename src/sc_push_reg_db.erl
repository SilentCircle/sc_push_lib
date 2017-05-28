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
        update_invalid_timestamps_by_svc_toks/1,
        delete_push_regs_by_tags/1,
        get_registration_info_by_device_id/1,
        get_registration_info_by_id/1,
        get_registration_info_by_svc_tok/1,
        get_registration_info_by_tag/1,
        is_valid_push_reg/1,
        init/1,
        make_id/2,
        make_sc_push_props/7,
        make_sc_push_props/8,
        make_svc_tok/2,
        reregister_ids/1,
        reregister_svc_toks/1,
        save_push_regs/1,
        from_posix_time_ms/1
    ]).

-export_type([
        reg_id_key/0,
        svc_tok_key/0
        ]).


%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-type reg_id_key() :: {binary(), binary()}.
-type svc_tok_key() :: {atom(), binary()}.
-type atom_or_str() :: atom() | string().
-type binable() :: atom() | binary() | integer() | iolist().
-type reg_id_keys() :: [reg_id_key()].

-type push_reg_list() :: list().

%% So this is pretty much hard-coded right now.
%% It would be preferable to generate the interface
%% module at run time.
-define(DB_MOD, sc_push_reg_db_mnesia).

%%====================================================================
%% API
%%====================================================================
init(Nodes) ->
    ?DB_MOD:init(Nodes).

all_registration_info() ->
    ?DB_MOD:all_registration_info().

%% @doc Return a list of all push registration records.
%% @deprecated For debug only.
-spec all_reg() -> push_reg_list().
all_reg() ->
    ?DB_MOD:all_reg().

%% @doc Check registration id key.
-spec check_id(reg_id_key()) -> reg_id_key().
check_id(ID) ->
    ?DB_MOD:check_id(ID).

%% @doc Check multiple registration id keys.
-spec check_ids(reg_id_keys()) -> reg_id_keys().
check_ids(IDs) ->
    ?DB_MOD:check_ids(IDs).

create_tables(Nodes) ->
    ?DB_MOD:create_tables(Nodes).

%% @doc Delete push registrations by device ids
-spec delete_push_regs_by_device_ids([binary()]) -> ok | {error, term()}.
delete_push_regs_by_device_ids(DeviceIDs) ->
    ?DB_MOD:delete_push_regs_by_device_ids(DeviceIDs).

%% @doc Delete push registrations by internal registration id.
-spec delete_push_regs_by_ids(reg_id_keys()) -> ok | {error, term()}.
delete_push_regs_by_ids(IDs) ->
    ?DB_MOD:delete_push_regs_by_ids(IDs).

%% @doc Delete push registrations by service-token.
-spec delete_push_regs_by_svc_toks([svc_tok_key()]) -> ok | {error, term()}.
delete_push_regs_by_svc_toks(SvcToks) ->
    ?DB_MOD:delete_push_regs_by_svc_toks(SvcToks).

%% @doc Update push registration invalid timestamp by service-token.
-spec update_invalid_timestamps_by_svc_toks([{svc_tok_key(), non_neg_integer()}]) -> ok | {error, term()}.
update_invalid_timestamps_by_svc_toks(SvcToksTs) ->
    ?DB_MOD:update_invalid_timestamps_by_svc_toks(SvcToksTs).

%% @doc Delete push registrations by tags.
-spec delete_push_regs_by_tags([binary()]) -> ok | {error, term()}.
delete_push_regs_by_tags(Tags) ->
    ?DB_MOD:delete_push_regs_by_tags(Tags).

%% @doc Get registration information by device id.
-spec get_registration_info_by_device_id(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_device_id(DeviceID) ->
    ?DB_MOD:get_registration_info_by_device_id(DeviceID).

%% @doc Get registration information by unique id.
%% @see make_id/2
-spec get_registration_info_by_id(reg_id_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_id(ID) ->
    ?DB_MOD:get_registration_info_by_id(ID).

%% @doc Get registration information by service-token.
%% @see make_svc_tok/2
-spec get_registration_info_by_svc_tok(svc_tok_key()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_svc_tok(SvcTok) ->
    ?DB_MOD:get_registration_info_by_svc_tok(SvcTok).

%% @doc Get registration information by tag.
-spec get_registration_info_by_tag(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(Tag) ->
    ?DB_MOD:get_registration_info_by_tag(Tag).

%% @doc Is push registration proplist valid?
-spec is_valid_push_reg(sc_types:proplist(atom(), term())) -> boolean().
is_valid_push_reg(PL) ->
    ?DB_MOD:is_valid_push_reg(PL).

%% @doc Convert to an opaque registration ID key.
-spec make_id(binable(), binable()) -> reg_id_key().
make_id(Id, Tag) ->
    case {sc_util:to_bin(Id), sc_util:to_bin(Tag)} of
        {<<_,_/binary>>, <<_,_/binary>>} = Key ->
            Key;
        _IdTag ->
            throw({invalid_id_or_tag, {Id, Tag}})
    end.

make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist, Mod) ->
    make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist, Mod,
                       {0, 0, 0}).

make_sc_push_props(Service, Token, DeviceId, Tag, AppId, Dist, Mod,
                   LastInvalidOn) ->
    [
        {device_id, sc_util:to_bin(DeviceId)},
        {service, sc_util:to_atom(Service)},
        {token, sc_util:to_bin(Token)},
        {tag, sc_util:to_bin(Tag)},
        {app_id, sc_util:to_bin(AppId)},
        {dist, sc_util:to_bin(Dist)},
        {modified, Mod},
        {last_invalid_on, LastInvalidOn}
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
    ?DB_MOD:save_push_regs(ListOfProplists).

%% @doc Re-register invalidated tokens
-spec reregister_ids([{reg_id_key(), binary()}]) -> ok.
reregister_ids(IDToks) ->
    ?DB_MOD:reregister_ids(IDToks).

%% @doc Re-register invalidated tokens by svc_tok
-spec reregister_svc_toks([{svc_tok_key(), binary()}]) -> ok.
reregister_svc_toks(SvcToks) ->
    ?DB_MOD:reregister_svc_toks(SvcToks).

%%--------------------------------------------------------------------
from_posix_time_ms(TimestampMs) ->
    {TimestampMs div 1000000000,
     TimestampMs rem 1000000000 div 1000,
     TimestampMs rem 1000 * 1000}.

