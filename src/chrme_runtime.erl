-module(chrme_runtime).
-export([evaluate/2, call_function_on/4, add_binding/2, remove_binding/2,
         on_exception_thrown/2, off_exception_thrown/2]).

%% Evaluate a JavaScript expression in the page
evaluate(Name, Expr0) ->
    Expr = chrme_util:maybe_to_binary(Expr0),
    case chrme_cdp:call(Name, <<"Runtime.evaluate">>, #{expression => Expr}) of
        {ok, Resp} ->
            Result = maps:get(<<"result">>, Resp),
            {ok, Result};
        Err ->
            Err
    end.

%% Call a function on a remote object
call_function_on(Name, ObjectId, FuncDecl0, Args) ->
    FuncDecl = chrme_util:maybe_to_binary(FuncDecl0),
    Params = #{objectId => ObjectId, functionDeclaration => FuncDecl, arguments => Args},
    case chrme_cdp:call(Name, <<"Runtime.callFunctionOn">>, Params) of
        {ok, Resp} ->
            Result = maps:get(<<"result">>, Resp),
            {ok, Result};
        Err ->
            Err
    end.

%% Add a binding in the runtime
add_binding(Name, BindingName0) ->
    NameBin = chrme_util:maybe_to_binary(BindingName0),
    chrme_cdp:call(Name, <<"Runtime.addBinding">>, #{name => NameBin}).

%% Remove a binding
remove_binding(Name, BindingName0) ->
    NameBin = chrme_util:maybe_to_binary(BindingName0),
    chrme_cdp:call(Name, <<"Runtime.removeBinding">>, #{name => NameBin}).

%% Subscribe to exceptionThrown events
on_exception_thrown(Name, Fun) ->
    Ref = make_ref(),
    CallbackName = {chrme_runtime, on_exception_thrown, Name, Ref},
    CallbackFun = fun
        (stop) -> false;
        (Msg = #{<<"method">> := <<"Runtime.exceptionThrown">>, <<"params">> := Params}) ->
            Fun(Params),
            true;
        (_) -> false
    end,
    chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
    Ref.

off_exception_thrown(Name, Ref) ->
    CallbackName = {chrme_runtime, on_exception_thrown, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.