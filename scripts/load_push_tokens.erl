
%%! -pa ebin
-module(load_push_tokens).
-mode(compile).
-compile(export_all).

%% This won't work until this becomes an escriptized project.
%% -include_libs("epgsql.hrl").
%% Hence the hack.
-type epgsql_type() :: atom() | {array, atom()} | {unknown_oid, integer()}.

-record(column, {
    name :: binary(),
    type :: epgsql_type(),
    size :: -1 | pos_integer(),
    modifier :: -1 | pos_integer(),
    format :: integer()
}).

-record(statement, {
    name :: string(),
    columns :: [#column{}],
    types :: [epgsql_type()]
}).

-record(error, {
    % see client_min_messages config option
    severity :: debug | log | info | notice | warning | error | fatal | panic,
    code :: binary(),
    codename :: atom(),
    message :: binary(),
    extra :: [{severity | detail | hint | position | internal_position | internal_query
               | where | schema_name | table_name | column_name | data_type_name
               | constraint_name | file | line | routine,
               binary()}]
}).

%%--------------------------------------------------------------------
%% main/1
%%--------------------------------------------------------------------
main([CSVFile, User, Pass, Db, Tablename]) ->
    main([CSVFile, User, Pass, Db, Tablename, "regular"]);
main([CSVFile, User, Pass, Db, Tablename, SExecType]) ->
    ExecType = strlower_to_atom(SExecType),
    true = lists:member(ExecType, [regular, batch]),
    {ok, B} = file:read_file(CSVFile),
    [Header | BRecs] = binary:split(B, <<"\n">>, [global]),
    load_pg(User, Pass, Db, Tablename, Header, BRecs, ExecType);
main(_) ->
    msg("usage: ~s csv-file-with-header user password database tablename [regular|batch]\n",
        [filename:basename(escript:script_name())]),
    halt(1).

%%--------------------------------------------------------------------
load_pg(User, Pass, Db, TableName, Header, BRecs, ExecType) ->
    ColList = make_column_list(Header),
    NRecs = length(BRecs),

    msg("Column names: ~s\n", [Header]),
    msg("~B records to load\n", [NRecs]),
    ElapsedMicros = do_load(ExecType, User, Pass, Db, TableName, ColList, BRecs),

    Elapsed = ElapsedMicros / 1.0e6,
    TxnRate = NRecs / Elapsed,
    msg("Ended load at ~p (~.1f s, ~.1f recs/s)\n",
        [calendar:local_time(), Elapsed, TxnRate]).

%%--------------------------------------------------------------------
do_load(ExecType, User, Pass, Db, TableName, ColList, BRecs) ->
    {ok, C} = epgsql:connect("localhost", User, Pass, [{database, Db}]),
    Types = [Col#column.type || Col <- get_columns(C, TableName, ColList)],
    NCols = length(ColList),
    %Recs = [convert(L) || B <- BRecs, length(L = split_csv(B)) =:= NCols],
    Recs = [convert_cvs(Types, L) || B <- BRecs, length(L = split_csv(B)) =:= NCols],
    msg("~p: Connected to db\n", [calendar:local_time()]),
    msg("~p: Starting ~p load\n", [calendar:local_time(), ExecType]),
    ElapsedMicros = do_query(ExecType, C, TableName, ColList, Recs),
    msg("~p: Ended load\n", [calendar:local_time()]),
    ok = epgsql:close(C),
    msg("~p: Closed db\n", [calendar:local_time()]),
    ElapsedMicros.

%%--------------------------------------------------------------------
do_query(regular, C, TableName, ColList, Recs) ->
    Query = make_insert_query(TableName, ColList),
    msg("Query: [~s]\n", [Query]),
    Txn = fun(Conn) ->
                  lists:foreach(fun(Rec) ->
                                        epgsql:equery(Conn, Query, Rec)
                                end, Recs)
          end,
    {ElapsedMicros, ok} = timer:tc(epgsql, with_transaction, [C, Txn]),
    ElapsedMicros;
do_query(batch, C, TableName, ColList, Recs) ->
    Columns = get_columns(C, TableName, ColList),
    Types = [Col#column.type || Col <- Columns],
    Query = make_insert_query(TableName, ColList),
    msg("Query: [~s]\n", [Query]),
    {ok, BeginTxn} = epgsql:parse(C, "BEGIN", []),
    {ok, Stmt} = epgsql:parse(C, "S1", Query, Types),
    {ok, CommitTxn} = epgsql:parse(C, "COMMIT", []),
    Batch = [{BeginTxn, []}] ++ [{Stmt, BindParams} || BindParams <- Recs] ++ [{CommitTxn, []}],
    %msg("DEBUG: Batch (first 3 recs) = ~p\n", [lists:sublist(Batch, 3)]),
    {ElapsedMicros, [_|_]=Ret} = timer:tc(epgsql, execute_batch, [C, Batch]),
    lists:foreach(fun({{Status, P2}, RecNo}) ->
                          case Status of
                              ok ->
                                  ok;
                              Err ->
                                  throw({error, {msg, Status, p2, P2, rec, lists:nth(RecNo, Batch)}})
                          end
                  end, lists:zip(Ret, lists:seq(1, length(Ret)))),
    ElapsedMicros.

%%--------------------------------------------------------------------
get_columns(Conn, TableName, ColList) ->
    SColList = string:join(ColList, ","),
    {ok, St} = epgsql:parse(Conn, "select " ++ SColList ++ " from " ++ TableName),
    St#statement.columns.

%%--------------------------------------------------------------------
make_insert_query(TableName, ColList) ->
    NCols = length(ColList),
    "insert into " ++ TableName ++ " (" ++ string:join(ColList, ",") ++ ")"
    " values " ++ make_values_list(NCols).

%%--------------------------------------------------------------------
make_column_list(Header) ->
    [binary_to_list(Col) || Col <- split_csv(Header)].

%%--------------------------------------------------------------------
%% -> "($1,$2,...,$Ncols)"
make_values_list(NCols) ->
    DollarVals = ["$" ++ integer_to_list(N) || N <- lists:seq(1, NCols)],
    "(" ++ string:join(DollarVals, ",") ++ ")".

%%--------------------------------------------------------------------
split_csv(<<Rec/binary>>) ->
    binary:split(Rec, <<",">>, [global]).

%%--------------------------------------------------------------------
convert([Id, UUID, Type, Token, AppId, CreatedTS, ModifiedTS, LastDevid]) ->
    [binary_to_integer(Id),
     UUID, Type, Token, AppId,
     pg_timestamp2dt(CreatedTS),
     pg_timestamp2dt(ModifiedTS),
     LastDevid].


%%--------------------------------------------------------------------
%% Convert binary string representations from the CSV into internal Erlang.
%% There is limited support because I haven't had time to look at how
%% PG generates CSV formats for all data types.
%%
%% Required: columns and vals are in corresponding order, same lengths
%% Vals is a list of binary strings.
%%
%% Here's a table for each data type with the actual output from epgsql:equery,
%% that is, what it expects.
%%
%% However, the CSV value looks different (see table 2).
%%
%% Table 1: Expected input formats for epgsql:equery.
%%
%% Column name         Type               Value
%% -----------         ----               -----
%% id                  int4               1
%% null_field          varchar            null
%% c_bigint            int8               100
%% c_bigserial         int8               1
%% c_bit               bit                <<"11110000111100001111000011110000">>
%% c_bit_varying       varbit             <<"11111111">>
%% c_boolean_true      bool               true
%% c_boolean_false     bool               false
%% c_box               box                <<"(1,1),(0,0)">>
%% c_bytea             bytea              <<"Êþº¾">>
%% c_character         bpchar             <<"character32                     ">>
%% c_character_varying varchar            <<"character_varying32">>
%% c_cidr              cidr               {{192,168,100,128},25}
%% c_circle            circle             <<"<(0,0),1>">>
%% c_date              date               {2017,6,7}
%% c_double_precision  float8             3.141592653589793
%% c_inet              inet               {192,168,1,1}
%% c_integer           int4               102
%% c_integer_array2d   {array,int4}       [[1,2,3],[4,5,6],[7,8,9]]
%% c_interval          interval           {{0,7,6.123456},8,129}
%% c_interval_y        interval           {{0,0,0.0},0,108}
%% c_interval_m        interval           {{0,0,0.0},0,8}
%% c_interval_d        interval           {{0,0,0.0},7,0}
%% c_interval_h        interval           {{6,0,0.0},0,0}
%% c_interval_min      interval           {{0,5,0.0},0,0}
%% c_interval_s        interval           {{0,0,4.123456},0,0}
%% c_interval_y2m      interval           {{0,0,0.0},0,129}
%% c_interval_d2h      interval           {{6,0,0.0},7,0}
%% c_interval_d2m      interval           {{6,5,0.0},7,0}
%% c_interval_d2s      interval           {{6,5,4.234567},7,0}
%% c_interval_h2m      interval           {{10,59,0.0},0,0}
%% c_interval_h2s      interval           {{10,59,2.345678},0,0}
%% c_interval_m2s      interval           {{0,10,15.123456},0,0}
%% c_json              json               <<"{\"product\": \"PostgreSQL\", \"version\": 9.4, \"jsonb\":false, \"a\":[1,2,3]}">>
%% c_jsonb             jsonb              <<"{\"a\": [1, 2, 3], \"jsonb\": true, \"product\": \"PostgreSQL\", \"version\": 9.4}">>
%% c_line              line               <<"{1,-1,0}">>
%% c_lseg              lseg               <<"[(0,0),(0,1)]">>
%% c_macaddr           macaddr            <<"08:00:2b:01:02:03">>
%% c_money             cash               <<"$1,234,567.89">>
%% c_numeric           numeric            <<"1234567890.0123456789">>
%% c_path              path               <<"((0,1),(1,2),(2,3))">>
%% c_pg_lsn            {unknown_oid,3220} <<"ABCD/CDEF">>
%% c_point             point              {10.0,10.0}
%% c_polygon           polygon            <<"((0,0),(0,1),(1,1),(1,0))">>
%% c_real              float4             2.718280076980591
%% c_smallint          int2               42
%% c_smallserial       int2               1
%% c_text              text               <<"No man is an iland, entire of itself;">>
%% c_time              time               {4,5,6.345678}
%% c_timestamp         timestamp          {{2017,6,5},{4,5,6.789}}
%% c_timestamp_tz      timestamptz        {{2017,6,5},{8,5,6.789}}
%% c_tsquery           tsquery            <<"'fat' & ( 'rat' | 'cat' )">>
%% c_tsvector          tsvector           <<"'a' 'and' 'ate' 'cat' 'fat' 'mat' 'on' 'rat' 'sat'">>
%% c_txid_snapshot     {unknown_oid,2970} null
%% c_uuid              uuid               <<"1a54f33b-f891-45f6-bf8d-5e6fd36af617">>
%% c_xml               xml                <<"<html><head/><body/></html>">>
%%
%% Table 2: Output from PG select
%%
%% Column name         Type               Value
%% -----------         ----               -----
%% id                  int4               1
%% null_field          varchar
%% c_bigint            int8               100
%% c_bigserial         int8               1
%% c_bit               bit                11110000111100001111000011110000
%% c_bit_varying       varbit             11111111
%% c_boolean_true      bool               t
%% c_boolean_false     bool               f
%% c_box               box                (1,1),(0,0)
%% c_bytea             bytea              \xcafebabe
%% c_character         bpchar             character32
%% c_character_varying varchar            character_varying32
%% c_cidr              cidr               192.168.100.128/25
%% c_circle            circle             <(0,0),1>
%% c_date              date               2017-06-07
%% c_double_precision  float8             3.14159265358979
%% c_inet              inet               192.168.1.1
%% c_integer           int4               102
%% c_integer_array2d   {array,int4}       {{1,2,3},{4,5,6},{7,8,9}}
%% c_interval          interval           10 years 9 mons 8 days 00:07:06.123456
%% c_interval_y        interval           9 years
%% c_interval_m        interval           8 mons
%% c_interval_d        interval           7 days
%% c_interval_h        interval           06:00:00
%% c_interval_min      interval           00:05:00
%% c_interval_s        interval           00:00:04.123456
%% c_interval_y2m      interval           10 years 9 mons
%% c_interval_d2h      interval           7 days 06:00:00
%% c_interval_d2m      interval           7 days 06:05:00
%% c_interval_d2s      interval           7 days 06:05:04.234567
%% c_interval_h2m      interval           10:59:00
%% c_interval_h2s      interval           10:59:02.345678
%% c_interval_m2s      interval           00:10:15.123456
%% c_json              json               {"product": "PostgreSQL", "version": 9.4, "jsonb":false, "a":[1,2,3]}
%% c_jsonb             jsonb              {"a": [1, 2, 3], "jsonb": true, "product": "PostgreSQL", "version": 9.4}
%% c_line              line               {1,-1,0}
%% c_lseg              lseg               [(0,0),(0,1)]
%% c_macaddr           macaddr            08:00:2b:01:02:03
%% c_money             cash               $1,234,567.89
%% c_numeric           numeric            1234567890.0123456789
%% c_path              path               ((0,1),(1,2),(2,3))
%% c_pg_lsn            {unknown_oid,3220} ABCD/CDEF
%% c_point             point              (10,10)
%% c_polygon           polygon            ((0,0),(0,1),(1,1),(1,0))
%% c_real              float4             2.71828
%% c_smallint          int2               42
%% c_smallserial       int2               1
%% c_text              text               No man is an iland, entire of itself;
%% c_time              time               04:05:06.345678
%% c_timestamp         timestamp          2017-06-05 04:05:06.789
%% c_timestamp_tz      timestamptz        2017-06-05 04:05:06.789-04
%% c_tsquery           tsquery            'fat' & ( 'rat' | 'cat' )
%% c_tsvector          tsvector           'a' 'and' 'ate' 'cat' 'fat' 'mat' 'on' 'rat' 'sat'
%% c_txid_snapshot     {unknown_oid,2970}
%% c_uuid              uuid               1a54f33b-f891-45f6-bf8d-5e6fd36af617
%% c_xml               xml                <html><head/><body/></html>

convert_cvs(Types, Vals) when length(Types) =:= length(Vals) ->
    lists:foldr(fun({Type, Val}, Acc) ->
                        %msg("DEBUG: Type: ~p, Val: ~p\n", [Type, Val]),
                        [convert(Type, Val) | Acc]
                end, [], lists:zip(Types, Vals)).


%%--------------------------------------------------------------------
%% FIXME: Convert rest of types from Postgres display output, including
%% inverval and bytea
%%--------------------------------------------------------------------
convert(Type, Val) ->
    %msg("DEBUG: convert(~p, ~p)\n", [Type, Val]),
    convert2(Type, Val).

convert2(_,             <<>>)           -> default;
convert2(bool,          <<"f">>)        -> false;
convert2(bool,          <<"t">>)        -> true;
convert2(bytea,         <<Val/binary>>) -> Val; % FIXME
convert2(date,          <<Val/binary>>) -> pg_date2d(Val);
convert2(float4,        <<Val/binary>>) -> b2f(Val);
convert2(float8,        <<Val/binary>>) -> b2f(Val);
convert2(int2,          <<Val/binary>>) -> b2i(Val);
convert2(int4,          <<Val/binary>>) -> b2i(Val);
convert2(int8,          <<Val/binary>>) -> b2i(Val);
convert2(interval,      <<Val/binary>>) -> pginterval2iv(Val);
convert2(json,          <<Val/binary>>) -> Val;
convert2(jsonb,         <<Val/binary>>) -> Val;
convert2(text,          <<Val/binary>>) -> Val;
convert2(time,          <<Val/binary>>) -> pg_time2t(Val);
convert2(timestamp,     <<Val/binary>>) -> pg_timestamp2dt(Val);
convert2(timestamptz,   <<Val/binary>>) -> pg_timestamp2dt(Val);
convert2(uuid,          <<Val/binary>>) -> Val;
convert2(varchar,       <<Val/binary>>) -> Val;
convert2(Type,          Val)            -> throw({unsupported_type_val, {Type, Val}}).

%%--------------------------------------------------------------------
pg_timestamp2dt(<<YMD:10/binary, $\s, HMSU/binary>>) ->
    {pg_date2d(YMD), pg_time2t(HMSU)};
pg_timestamp2dt(<<YMD:10/binary, $\s, HMS:8/binary>>) ->
    {pg_date2d(YMD), pg_time2t(HMS)}.

pg_date2d(<<Y:4/binary, $-, M:2/binary, $-, D:2/binary>>) ->
    pg_date2d(b2i(Y), b2i(M), b2i(D)).

pg_date2d(Y, M, S) ->
    {Y, M, S}.

pg_time2t(<<H:2/binary, $:, M:2/binary, $:, S:2/binary, $., US/binary>>) ->
    pg_time2t(b2i(H), b2i(M), b2f(<<S/binary, $., US/binary>>));
pg_time2t(<<H:2/binary, $:, M:2/binary, $:, S:2/binary>>) ->
    pg_time2t(b2i(H), b2i(M), b2i(S)).

pg_time2t(H, M, S) ->
    {H, M, S}.

-compile({inline, [{pg_date2d, 3},
                   {pg_time2t, 3},
                   {pg_timestamp2dt, 1}]}).

%%--------------------------------------------------------------------
pg_interval2iv(<<B/binary>>) ->
    throw({not_implemented, pg_interval2iv}.

%%--------------------------------------------------------------------
strlower_to_atom(S) ->
    list_to_atom(string:to_lower(S)).

%%--------------------------------------------------------------------
msg(Fmt, Args) ->
    io:format(standard_error, Fmt, Args).

%%--------------------------------------------------------------------
-compile({inline, [{b2i, 1},{b2f, 1}]}).
b2i(<<B/binary>>) ->
    binary_to_integer(B).

b2f(<<B/binary>>) ->
    binary_to_float(B).
