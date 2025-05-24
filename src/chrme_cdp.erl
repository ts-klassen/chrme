-module(chrme_cdp).
-export([call/3, subscribe_event/3, unsubscribe_event/2]).

%% Send a JSON-RPC method call over the Chrome DevTools WebSocket
call(Name, MethodBin, Params) ->
    JsonParams = params_to_json(Params),
    Json = #{<<"method">> => MethodBin, <<"params">> => JsonParams},
    Resp = chrme_ws_apic:await_send_response(Name, Json),
    case maps:get(<<"error">>, Resp, undefined) of
        undefined ->
            {ok, maps:get(<<"result">>, Resp, #{})};
        Err ->
            {error, Err}
    end.

%% Subscribe to a CDP event over the WebSocket
subscribe_event(Name, EventBin, Fun) ->
    Ref = make_ref(),
    CallbackName = {chrme_cdp, subscribe_event, Name, Ref},
    CallbackFun = fun
        (stop) ->
            false;
        (Msg = #{<<"method">> := EventBin}) ->
            Fun(Msg),
            true;
        (_) ->
            false
    end,
    chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
    Ref.

unsubscribe_event(Name, Ref) ->
    CallbackName = {chrme_cdp, subscribe_event, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName).

%% Convert an Erlang-map with atom or binary keys into a JSON-friendly map (binary keys)
params_to_json(Params) when is_map(Params) ->
    lists:foldl(fun({K, V}, Acc) ->
        KeyBin = key_to_binary(K),
        Value = val_to_json(V),
        maps:put(KeyBin, Value, Acc)
    end, #{}, maps:to_list(Params));
params_to_json(Other) ->
    Other.

key_to_binary(K) when is_atom(K) ->
    atom_to_binary(K, utf8);
key_to_binary(K) when is_binary(K) ->
    K;
key_to_binary(K) when is_list(K) ->
    list_to_binary(K).

val_to_json(V) when is_map(V) ->
    params_to_json(V);
val_to_json(V) when is_list(V) ->
    [val_to_json(E) || E <- V];
val_to_json(V) ->
    V.