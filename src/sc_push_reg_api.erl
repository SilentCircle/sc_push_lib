-module(sc_push_reg_api).

-export([
    init/0,
    register_id/1,
    register_ids/1,
    reregister_id/2,
    reregister_by_device_id/2,
    deregister_id/1,
    deregister_ids/1,
    deregister_tag/1,
    deregister_device_id/1,
    all_registration_info/0,
    get_registration_info/1,
    get_registration_info_by_id/1,
    get_registration_info_by_device_id/1,
    get_registration_info_by_tag/1,
    is_valid_push_reg/1,
    make_id/2
    ]).

-include("sc_push_lib.hrl").

%%--------------------------------------------------------------------
%% Types
%%--------------------------------------------------------------------
-type atom_or_str() :: atom() | string().
-type bin_or_str() :: binary() | string().
-type binable() :: atom() | binary() | integer() | iolist().
-type reg_id_keys() :: [sc_push_reg_db:reg_id_key()].

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
    sc_push_reg_db:reregister_id(OldId, NewToken).

%% @doc Reregister a previously-registered identity, substituting a new token
%% using the device id as a key. This assumes that there are no duplicate device
%% IDs globally. This will throw an exception otherwise.
-spec reregister_by_device_id(binary(), binary()) -> ok.
reregister_by_device_id(DevId, <<NewToken/binary>>) ->
    sc_push_reg_db:reregister_by_device_id(DevId, NewToken).

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

%% @doc Deregister all ids using a common tag
-spec deregister_tag(binary()) -> ok | {error, term()}.
deregister_tag(<<>>) ->
    {error, empty_tag};
deregister_tag(Tag) when is_binary(Tag) ->
    try
        sc_push_reg_db:delete_push_regs_by_tag(Tag)
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister all ids using a common tag
-spec deregister_device_id(string()|binary()) -> ok | {error, term()}.
deregister_device_id(DeviceId) when is_list(DeviceId) ->
    deregister_device_id(sc_util:to_bin(DeviceId));
deregister_device_id(<<>>) ->
    {error, empty_device_id};
deregister_device_id(DeviceId) when is_binary(DeviceId) ->
    try
        sc_push_reg_db:delete_push_regs_by_device_id([DeviceId])
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister a list of device IDs
-spec deregister_device_ids([string()|binary()]) -> ok | {error, term()}.
deregister_device_ids(IDs) when is_list(IDs) ->
    try
        sc_push_reg_db:delete_push_regs_by_device_id(IDs)
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Deregister an identity using a key returned by make_id/2.
-spec deregister_id(sc_push_reg_db:reg_id_key()) -> ok | {error, term()}.
deregister_id(ID) ->
    deregister_ids([ID]).

%% @doc Deregister a list of identities.
-spec deregister_ids(reg_id_keys()) -> ok | {error, term()}.
deregister_ids(IDs) when is_list(IDs) ->
    try
        CheckedIDs = sc_push_reg_db:check_ids(IDs),
        sc_push_reg_db:delete_push_regs(CheckedIDs)
    catch
        _:Reason ->
            {error, Reason}
    end.

%% @doc Get the registration information for a tag.
-spec get_registration_info(bin_or_str()) -> [sc_types:reg_proplist()] | notfound.
get_registration_info(Tag) ->
    get_registration_info_by_tag(sc_util:to_bin(Tag)).

-spec get_registration_info_by_tag(binary()) ->
    list(sc_types:reg_proplist()) | notfound.
get_registration_info_by_tag(Tag) ->
    sc_push_reg_db:get_registration_info_by_tag(Tag).

%% @doc Get the registration information using a key returned by make_id/2.
-spec get_registration_info_by_id(sc_push_reg_db:reg_id_key()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info_by_id(ID) ->
    sc_push_reg_db:get_registration_info_by_id(ID).

%% @doc Get the registration information using device_id
-spec get_registration_info_by_device_id(binary()) ->
    sc_types:reg_proplist() | notfound.
get_registration_info_by_device_id(ID) ->
    sc_push_reg_db:get_registration_info_by_device_id(ID).

%% @doc Validate push registration proplist.
-spec is_valid_push_reg(list()) -> boolean().
is_valid_push_reg(PL) ->
    sc_push_reg_db:is_valid_push_reg(PL).

%% @doc Create an opaque registration ID key for use with other functions
%% in this API.
-spec make_id(atom_or_str(), binable()) -> sc_push_reg_db:reg_id_key().
make_id(Service, Token) ->
    sc_push_reg_db:make_id(Service, Token).

%%====================================================================
%% Internal functions
%%====================================================================

