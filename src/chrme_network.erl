-module(chrme_network).
-export([enable/1, disable/1, set_request_interception/2,
         continue_intercepted_request/2, emulate_network_conditions/2,
         on_request_will_be_sent/2, off_request_will_be_sent/2]).

%% Enable network tracking
enable(Name) ->
    chrme_cdp:call(Name, <<"Network.enable">>, #{}).

%% Disable network tracking
disable(Name) ->
    chrme_cdp:call(Name, <<"Network.disable">>, #{}).

%% Set patterns for request interception
set_request_interception(Name, Patterns) ->
    chrme_cdp:call(Name, <<"Network.setRequestInterception">>, #{patterns => Patterns}).

%% Continue an intercepted request
continue_intercepted_request(Name, RequestId) ->
    chrme_cdp:call(Name, <<"Network.continueInterceptedRequest">>, #{requestId => RequestId}).

%% Emulate network conditions (offline, latency, throughput)
emulate_network_conditions(Name, Conditions) ->
    chrme_cdp:call(Name, <<"Network.emulateNetworkConditions">>, Conditions).

%% Subscribe to requestWillBeSent events
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
off_request_will_be_sent(Name, Ref) ->
    CallbackName = {chrme_network, on_request_will_be_sent, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.