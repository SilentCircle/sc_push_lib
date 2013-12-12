-module(sc_push_reg_api).

-export([
    init/0,
    register_id/1,
    register_ids/1,
    reregister_id/2,
    deregister_id/1,
    deregister_ids/1,
    deregister_tag/1,
    deregister_tags/1,
    deregister_svc_tok/1,
    deregister_svc_toks/1,
    deregister_device_id/1,
    deregister_device_ids/1,
    all_registration_info/0,
    get_registration_info/1,
    get_registration_info_by_id/1,
    get_registration_info_by_id/2,
    get_registration_info_by_tag/1,
    get_registration_info_by_device_id/1,
    get_registration_info_by_svc_tok/1,
    get_registration_info_by_svc_tok/2,
    is_valid_push_reg/1,
    make_id/2,
    make_svc_tok/2
    ]).

-include("sc_push_lib.hrl").

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-type atom_or_str() :: atom() | string().
-type bin_or_str() :: binary() | string().

%%====================================================================
%% API
%%====================================================================
%% @doc Initialize API.
-spec init() -> ok.
init() ->
    sc_push_reg_db:create_tables([node()]),
    ok.

%% @doc Get registration info of all registered IDs. Note
%% that in future, this may be limited to the first 100
%% IDs found. It may also be supplemented by an API that
%% supports getting the information in batches.
-spec all_registration_info() -> [sc_types:reg_proplist()].
all_registration_info() ->
    sc_push_reg_db:all_registration_info().

%% @doc Reregister a previously-registered identity, substituting a new token
%% for the specified push service.
-spec reregister_id(sc_push_reg_db:reg_id_key(), binary()) -> ok.
reregister_id(OldId, <<NewToken/binary>>) ->
    sc_push_reg_db:reregister_ids([{OldId, NewToken}]).

%% @doc Register an identity for receiving push notifications
%% from a supported push service.
-spec register_id(sc_types:reg_proplist()) -> sc_types:reg_result().
register_id([{_, _}|_] = Props) ->
    register_ids([Props]).

%% @doc Register a list of identities that should receive push notifications.
-spec register_ids([sc_types:reg_proplist(), ...]) -> ok | {error, term()}.
register_ids([[{_, _}|_]|_] = ListOfProplists) ->
    try
        sc_push_reg_db:save_push_regs(ListOfProplists)
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister all registrations using a common tag
-spec deregister_tag(binary()) -> ok | {error, term()}.
deregister_tag(<<>>) ->
    {error, empty_tag};
deregister_tag(Tag) when is_binary(Tag) ->
    try
        sc_push_reg_db:delete_push_regs_by_tags([Tag])
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister all registrations corresponding to a list of tags.
-spec deregister_tags(list(binary())) -> ok | {error, term()}.
deregister_tags(Tags) when is_list(Tags) ->
    try
        sc_push_reg_db:delete_push_regs_by_tags(Tags)
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister all registrations using a common device ID
-spec deregister_device_id(binary()) -> ok | {error, term()}.
deregister_device_id(<<>>) ->
    {error, empty_device_id};
deregister_device_id(DeviceID) when is_binary(DeviceID) ->
    try
        sc_push_reg_db:delete_push_regs_by_device_ids([DeviceID])
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister all registrations corresponding to a list of device IDs.
-spec deregister_device_ids(list(binary())) -> ok | {error, term()}.
deregister_device_ids(DeviceIDs) when is_list(DeviceIDs) ->
    try
        sc_push_reg_db:delete_push_regs_by_device_ids(DeviceIDs)
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister all registrations with common service+push token
-spec deregister_svc_tok(sc_push_reg_db:svc_tok_key()) -> ok | {error, term()}.
deregister_svc_tok({_, <<>>}) ->
    {error, empty_token};
deregister_svc_tok({_, <<_/binary>>} = SvcTok) ->
    try
        sc_push_reg_db:delete_push_regs_by_svc_toks([make_svc_tok(SvcTok)])
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister all registrations corresponding to list of service-tokens.
-spec deregister_svc_toks([sc_push_reg_db:svc_tok_key()]) -> ok | {error, term()}.
deregister_svc_toks(SvcToks) when is_list(SvcToks) ->
    try
        sc_push_reg_db:delete_push_regs_by_svc_toks(to_svc_toks(SvcToks))
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister by id.
-spec deregister_id(sc_push_reg_db:reg_id_key()) -> ok | {error, term()}.
deregister_id(ID) ->
    deregister_ids([ID]).

%% @doc Deregister using list of ids.
-spec deregister_ids([sc_push_reg_db:reg_id_key()]) -> ok | {error, term()}.
deregister_ids([]) ->
    ok;
deregister_ids([{<<_/binary>>, <<_/binary>>}|_] = IDs) ->
    try
        sc_push_reg_db:delete_push_regs_by_ids(to_ids(IDs))
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Get registration information.
%% @equiv get_registration_info_by_tag/1
-spec get_registration_info(bin_or_str()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info(Tag) ->
    get_registration_info_by_tag(Tag).

%% @doc Get registration information by unique id.
%% @see make_id/2
-spec get_registration_info_by_id(sc_push_reg_db:reg_id_key()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info_by_id(ID) ->
    sc_push_reg_db:get_registration_info_by_id(ID).

%% @equiv get_registration_info_by_id/1
-spec get_registration_info_by_id(bin_or_str(), bin_or_str()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info_by_id(DeviceID, Tag) ->
    get_registration_info_by_id(make_id(DeviceID, Tag)).

%% @doc Get registration information by tag.
-spec get_registration_info_by_tag(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(Tag) ->
    sc_push_reg_db:get_registration_info_by_tag(Tag).

%% @doc Get registration information by device_id.
-spec get_registration_info_by_device_id(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_device_id(DeviceID) ->
    sc_push_reg_db:get_registration_info_by_device_id(DeviceID).

%% @doc Get registration information by service-token
%% @see make_svc_tok/2
-spec get_registration_info_by_svc_tok(sc_push_reg_db:svc_tok_key()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info_by_svc_tok(SvcTok) ->
    sc_push_reg_db:get_registration_info_by_svc_tok(SvcTok).

-spec get_registration_info_by_svc_tok(atom(), binary()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info_by_svc_tok(Svc, Tok) ->
    ?MODULE:get_registration_info_by_svc_tok(make_svc_tok(Svc, Tok)).

%% @doc Validate push registration proplist.
-spec is_valid_push_reg(list()) -> boolean().
is_valid_push_reg(PL) ->
    sc_push_reg_db:is_valid_push_reg(PL).

%% @doc Create a unique id from device_id and tag.
-compile({inline, [{make_id, 2}]}).
-spec make_id(bin_or_str(), bin_or_str()) -> sc_push_reg_db:reg_id_key().
make_id(DeviceID, Tag) ->
    sc_push_reg_db:make_id(DeviceID, Tag).

%% @equiv make_svc_tok/2
-compile({inline, [{make_svc_tok, 1}]}).
-spec make_svc_tok({atom_or_str(), bin_or_str()} | sc_push_reg_db:svc_tok_key())
    -> sc_push_reg_db:svc_tok_key().
make_svc_tok({Svc, Tok} = SvcTok) when is_atom(Svc), is_binary(Tok) ->
    SvcTok;
make_svc_tok({Svc, Tok}) ->
    make_svc_tok(Svc, Tok).

%% @doc Create service-token key
-compile({inline, [{make_svc_tok, 2}]}).
-spec make_svc_tok(atom_or_str(), bin_or_str()) -> sc_push_reg_db:svc_tok_key().
make_svc_tok(Svc, Tok) ->
    sc_push_reg_db:make_svc_tok(Svc, Tok).

%%====================================================================
%% Internal functions
%%====================================================================
-compile({inline, [{to_ids, 1}]}).
to_ids(IDs) ->
    [make_id(DeviceID, Tag) || {DeviceID, Tag} <- IDs].

-compile({inline, [{to_svc_toks, 1}]}).
to_svc_toks(SvcToks) ->
    [make_svc_tok(Svc, Tok) || {Svc, Tok} <- SvcToks].

