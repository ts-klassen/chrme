-module(chrme_network).
-export([enable/1, disable/1, set_request_interception/2,
         continue_intercepted_request/2, emulate_network_conditions/2,
         on_request_will_be_sent/2, off_request_will_be_sent/2]).

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
-spec continue_intercepted_request(Name :: chrme_session:name(), RequestId :: term()) -> {ok, map()} | {error, term()}.
continue_intercepted_request(Name, RequestId) ->
    chrme_cdp:call(Name, <<"Network.continueInterceptedRequest">>, #{requestId => RequestId}).

%% Emulate network conditions (offline, latency, throughput)
-spec emulate_network_conditions(Name :: chrme_session:name(), Conditions :: term()) -> {ok, map()} | {error, term()}.
emulate_network_conditions(Name, Conditions) ->
    chrme_cdp:call(Name, <<"Network.emulateNetworkConditions">>, Conditions).

%% Subscribe to requestWillBeSent events
-spec on_request_will_be_sent(Name :: chrme_session:name(), Fun :: fun((map()) -> any())) -> reference().
on_request_will_be_sent(Name, Fun) ->
    Ref = make_ref(),
    CallbackName = {chrme_network, on_request_will_be_sent, Name, Ref},
    CallbackFun = fun
        (stop) -> false;
        (Msg = #{<<"method">> := <<"Network.requestWillBeSent">>, <<"params">> := Params}) ->
            Fun(Params),
            true;
        (_) -> false
    end,
    chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
    Ref.

%% Unsubscribe from requestWillBeSent
-spec off_request_will_be_sent(Name :: chrme_session:name(), Ref :: reference()) -> ok.
off_request_will_be_sent(Name, Ref) ->
    CallbackName = {chrme_network, on_request_will_be_sent, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.