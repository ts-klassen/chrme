-module(chrme_network).

-export_type([request_id/0]).

-type request_id() :: klsn:binstr().
-export([enable/1, disable/1, set_request_interception/2,
         continue_intercepted_request/2, emulate_network_conditions/2,
         register_request_will_be_sent_handler/2, unregister_request_will_be_sent_handler/2,
         register_event_handler/2, unregister_event_handler/2,
         register_response_received_handler/2, unregister_response_received_handler/2,
         register_loading_finished_handler/2, unregister_loading_finished_handler/2,
         get_response_body/2, await_response_body/3, await_response_body/2]).

%% Enable network tracking
-spec enable(Name :: chrme_session:name()) -> {ok, map()} | {error, term()}.
enable(Name) ->
    chrme_cdp:call(Name, <<"Network.enable">>, #{}).

%% Disable network tracking
-spec disable(Name :: chrme_session:name()) -> {ok, map()} | {error, term()}.
disable(Name) ->
    chrme_cdp:call(Name, <<"Network.disable">>, #{}).

%% Set patterns for request interception
-spec set_request_interception(Name :: chrme_session:name(), Patterns :: term()) -> {ok, map()} | {error, term()}.
set_request_interception(Name, Patterns) ->
    chrme_cdp:call(Name, <<"Network.setRequestInterception">>, #{patterns => Patterns}).

%% Continue an intercepted request
-spec continue_intercepted_request(Name :: chrme_session:name(), RequestId :: request_id()) -> {ok, map()} | {error, term()}.
continue_intercepted_request(Name, RequestId) ->
    chrme_cdp:call(Name, <<"Network.continueInterceptedRequest">>, #{requestId => RequestId}).

%% Emulate network conditions (offline, latency, throughput)
-spec emulate_network_conditions(Name :: chrme_session:name(), Conditions :: term()) -> {ok, map()} | {error, term()}.
emulate_network_conditions(Name, Conditions) ->
    chrme_cdp:call(Name, <<"Network.emulateNetworkConditions">>, Conditions).

%% Subscribe to requestWillBeSent events
-spec register_request_will_be_sent_handler(Name :: chrme_session:name(), Fun :: fun((map()) -> any())) -> reference().
register_request_will_be_sent_handler(Name, Fun) ->
    Ref = make_ref(),
    CallbackName = {chrme_network, register_request_will_be_sent_handler, Name, Ref},
    CallbackFun = fun
        (stop) -> false;
        (_Msg = #{<<"method">> := <<"Network.requestWillBeSent">>, <<"params">> := Params}) ->
            Fun(Params),
            true;
        (_) -> false
    end,
    chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
    Ref.

%% Unsubscribe from requestWillBeSent
-spec unregister_request_will_be_sent_handler(Name :: chrme_session:name(), Ref :: reference()) -> ok.
unregister_request_will_be_sent_handler(Name, Ref) ->
    CallbackName = {chrme_network, register_request_will_be_sent_handler, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.

%% ------------------------------------------------------------------
%%  Await response body helper
%% ------------------------------------------------------------------

-spec await_response_body(chrme_session:name(), request_id(), non_neg_integer()) ->
          {ok, binary(), boolean()} | {error, timeout | term()}.
await_response_body(Name, ReqId, Timeout) when is_integer(Timeout), Timeout >= 0 ->
    Start = erlang:monotonic_time(millisecond),
    Poll = fun This() ->
        case get_response_body(Name, ReqId) of
            {ok, _Body, _Enc} = Success ->
                Success;
            _ ->
                Now = erlang:monotonic_time(millisecond),
                case Now - Start >= Timeout of
                    true -> {error, timeout};
                    false ->
                        timer:sleep(100),
                        This()
                end
        end
    end,
    Poll().

-spec await_response_body(chrme_session:name(), request_id()) ->
          {ok, binary(), boolean()} | {error, timeout | term()}.
await_response_body(Name, ReqId) ->
    await_response_body(Name, ReqId, 5000).

%% ------------------------------------------------------------------
%%  Convenience: fetch response body for a completed request.
%%  Wraps the CDP method Network.getResponseBody
%% ------------------------------------------------------------------

%% Return the response body (potentially base64-encoded) for the given
%% requestId. The tuple is {ok, BodyBin, IsBase64Encoded} so the caller
%% can decide whether to decode.

-spec get_response_body(Name :: chrme_session:name(),
                       RequestId :: request_id()) ->
          {ok, binary(), boolean()} | {error, term()}.
get_response_body(Name, RequestId) ->
    case chrme_cdp:call(Name, <<"Network.getResponseBody">>, #{requestId => RequestId}) of
        {ok, #{<<"body">> := Body, <<"base64Encoded">> := Encoded}} ->
            {ok, Body, Encoded};
        Other ->
            Other
    end.

%% ------------------------------------------------------------------
%%  New convenience: listen to *all* Network domain events.
%% ------------------------------------------------------------------

%% Subscribe to every "Network.*" event.
-spec register_event_handler(Name :: chrme_session:name(),
                             Fun  :: fun((map()) -> any())) -> reference().
register_event_handler(Name, Fun) ->
    Ref = make_ref(),
    CallbackName = {chrme_network, register_event_handler, Name, Ref},
    CallbackFun = fun
        (stop) ->
            false;
        (Msg = #{<<"method">> := Method}) ->
            case Method of
                <<"Network.", _/binary>> ->
                    Fun(Msg),
                    true;
                _ ->
                    false
            end;
        (_) ->
            false
    end,
    chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
    Ref.

%% Unsubscribe from all Network.* events.
-spec unregister_event_handler(Name :: chrme_session:name(), Ref :: reference()) -> ok.
unregister_event_handler(Name, Ref) ->
    CallbackName = {chrme_network, register_event_handler, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.

%% ------------------------------------------------------------------
%%  One-off helpers for other common Network events
%% ------------------------------------------------------------------

%% responseReceived --------------------------------------------------

-spec register_response_received_handler(chrme_session:name(), fun((map()) -> any())) -> reference().
register_response_received_handler(Name, Fun) ->
    Ref = make_ref(),
    CbName = {chrme_network, response_received, Name, Ref},
    CbFun = fun
        (stop) -> false;
        (#{<<"method">> := <<"Network.responseReceived">>, <<"params">> := Params}) ->
            Fun(Params),
            true;
        (_) -> false
    end,
    chrme_ws_apic:add_callback(Name, {CbName, CbFun}),
    Ref.

-spec unregister_response_received_handler(chrme_session:name(), reference()) -> ok.
unregister_response_received_handler(Name, Ref) ->
    CbName = {chrme_network, response_received, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CbName),
    ok.

%% loadingFinished ---------------------------------------------------

-spec register_loading_finished_handler(chrme_session:name(), fun((map()) -> any())) -> reference().
register_loading_finished_handler(Name, Fun) ->
    Ref = make_ref(),
    CbName = {chrme_network, loading_finished, Name, Ref},
    CbFun = fun
        (stop) -> false;
        (#{<<"method">> := <<"Network.loadingFinished">>, <<"params">> := Params}) ->
            Fun(Params),
            true;
        (_) -> false
    end,
    chrme_ws_apic:add_callback(Name, {CbName, CbFun}),
    Ref.

-spec unregister_loading_finished_handler(chrme_session:name(), reference()) -> ok.
unregister_loading_finished_handler(Name, Ref) ->
    CbName = {chrme_network, loading_finished, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CbName),
    ok.