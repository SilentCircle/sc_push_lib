-module(sc_push_lib_test_helper).

-export([
         lager_config/2
        ]).

-include("test_assertions.hrl").

%%%===================================================================
%%% API
%%%===================================================================

%%====================================================================
%% Lager support
%%====================================================================
lager_config(Config, RawLagerConfig) ->
    PrivDir = proplists:get_value(priv_dir, Config),
    ?assert(PrivDir /= undefined),

    Replacements = [
                    {error_log_file, filename:join(PrivDir, "error.log")},
                    {console_log_file, filename:join(PrivDir, "console.log")},
                    {crash_log_file, filename:join(PrivDir, "crash.log")}
                   ],

    replace_template_vars(RawLagerConfig, Replacements).

replace_template_vars(RawLagerConfig, Replacements) ->
    Ctx = dict:from_list(Replacements),
    Str = lists:flatten(io_lib:fwrite("~1000p~s", [RawLagerConfig, "."])),
    SConfig = mustache:render(Str, Ctx),
    {ok, Tokens, _} = erl_scan:string(SConfig),
    {ok, LagerConfig} = erl_parse:parse_term(Tokens),
    LagerConfig.

