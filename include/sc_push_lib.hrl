-ifndef(sc_push_lib_hrl).
-define(sc_push_lib_hrl, true).

%%--------------------------------------------------------------------
%% Defines
%%--------------------------------------------------------------------
-define(SECONDS, 1).
-define(MINUTES, (60 * ?SECONDS)).
-define(HOURS,   (60 * ?MINUTES)).
-define(DAYS,    (24 * ?HOURS)).
-define(WEEKS,   ( 7 * ?DAYS)).

%%--------------------------------------------------------------------
%% Records
%%--------------------------------------------------------------------
-record(xmlcdata, {cdata = <<>>}).

-record(xmlelement, {
        name  = "" :: string(),
        attrs = [] :: list({string(), string()}),
        els   = [] :: list(#xmlelement{} | #xmlcdata{})
    }).

-endif.
