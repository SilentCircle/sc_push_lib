-ifndef(TEST_ASSERTIONS_HRL__).
-define (TEST_ASSERTIONS_HRL__, true).

-define(assertMsg(Cond, Fmt, Args),
    case (Cond) of
        true ->
            ok;
        false ->
            ct:fail("Assertion failed: ~p~n" ++ Fmt, [??Cond] ++ Args)
    end
).

-define(assert(Cond), ?assertMsg((Cond), "", [])).
-define(
    assertEqual(LHS, RHS),
        ?assertMsg(
            LHS == RHS,
            "~s=~p, ~s=~p", [??LHS, LHS, ??RHS, RHS]
        )
).
-define(assertThrow(Expr, Class, Reason),
    begin
            ok = (fun() ->
                    try (Expr) of
                        Res ->
                            {unexpected_return, Res}
                    catch
                        C:R ->
                            case {C, R} of
                                {Class, Reason} ->
                                    ok;
                                _ ->
                                    {unexpected_exception, {C, R}}
                            end
                    end
            end)()
    end
).

-endif.
