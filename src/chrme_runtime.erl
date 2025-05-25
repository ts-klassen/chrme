-module(chrme_runtime).
-export([evaluate/2, call_function_on/4, add_binding/2, remove_binding/2,
         register_exception_thrown_handler/2, unregister_exception_thrown_handler/2]).

%% Evaluate a JavaScript expression in the page
evaluate(Name, Expr0) ->
    Expr = chrme_util:to_binary(Expr0),
    case chrme_cdp:call(Name, <<"Runtime.evaluate">>, #{expression => Expr}) of
        {ok, Resp} ->
            Result = maps:get(<<"result">>, Resp),
            {ok, Result};
        Err ->
            Err
    end.

%% Call a function on a remote object
call_function_on(Name, ObjectId, FuncDecl0, Args) ->
    FuncDecl = chrme_util:to_binary(FuncDecl0),
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
    NameBin = chrme_util:to_binary(BindingName0),
    chrme_cdp:call(Name, <<"Runtime.addBinding">>, #{name => NameBin}).

%% Remove a binding
remove_binding(Name, BindingName0) ->
    NameBin = chrme_util:to_binary(BindingName0),
    chrme_cdp:call(Name, <<"Runtime.removeBinding">>, #{name => NameBin}).

%% Subscribe to exceptionThrown events
-spec register_exception_thrown_handler(Name :: chrme_session:name(), Fun :: fun((map()) -> any())) -> reference().
register_exception_thrown_handler(Name, Fun) ->
    Ref = make_ref(),
    CallbackName = {chrme_runtime, register_exception_thrown_handler, Name, Ref},
    CallbackFun = fun
        (stop) -> false;
        (Msg = #{<<"method">> := <<"Runtime.exceptionThrown">>, <<"params">> := Params}) ->
            Fun(Params),
            true;
        (_) -> false
    end,
    chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
    Ref.

%% Unsubscribe from exceptionThrown events
-spec unregister_exception_thrown_handler(Name :: chrme_session:name(), Ref :: reference()) -> ok.
unregister_exception_thrown_handler(Name, Ref) ->
    CallbackName = {chrme_runtime, register_exception_thrown_handler, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.