-module(chrme_session_SUITE).
-include_lib("common_test/include/ct.hrl").

%% Exported callbacks --------------------------------------------------------

-export([all/0, simple/1, network_events/1, event_handler/1, response_body/1]).

%% Test case list ------------------------------------------------------------

all() ->
    [simple, network_events, event_handler, response_body].

%%---------------------------------------------------------------------------
%% Test cases
%%---------------------------------------------------------------------------

simple(_Config) ->
    application:ensure_all_started(chrme),
    %% 1. Pick a free TCP port that we will pass to Chrome's
    %%    --remote-debugging-port flag. We simply open a listening
    %%    socket on port 0 (meaning "any"), read the assigned port and
    %%    close it again.
    {ok, LSock} = gen_tcp:listen(0, [binary, {active, false}]),
    {ok, {_, Port}} = inet:sockname(LSock),
    ok = gen_tcp:close(LSock),

    %% 2. Prepare a unique user-data-dir. Re-using the same profile in
    %%    multiple concurrent test runs can lead to Chrome exiting with
    %%    error code 21 (profile in use).
    UserDataDir = list_to_binary(io_lib:format("/tmp/chrme_ud_~p", [Port])),

    %% 3. Start a headless Chrome that listens on this port.
    LauncherOpts = #{ name          => launch1,
                      remote_port   => Port,
                      user_data_dir => UserDataDir,
                      headless      => true,
                      extra_args    => [ <<"--remote-allow-origins=*">> ]
                    },
    {ok, _PidLaunch} = chrme_launcher:start_link(LauncherOpts),
    ok = chrme_launcher:await_start(launch1),

    try

        %% 4. start a session to `https://example.com`
        {ok, Session} = chrme_session:start_link(session1,
                                           <<"localhost">>,
                                           Port,
                                           <<"https://example.com">>),
        ok = chrme_session:await_start(session1),

        %% 5. Read page title via Runtime.evaluate/2
        GetTitle = fun This() ->
            case chrme_runtime:evaluate(session1, <<"document.title">>) of
                {ok, #{<<"value">>:=<<>>}} ->
                    timer:sleep(100),
                    This();
                {ok, #{<<"value">>:=Title0}} ->
                    Title0
            end
        end,
        Title = GetTitle(),
        case Title of
            <<"Example Domain">> -> ok;
            _ -> ct:fail({unexpected_title, Title})
        end,

        %% 6. Retrieve the first <h1> element using the DOM domain.
        {ok, RootNode} = chrme_dom:get_document(session1),
        RootId        = maps:get(<<"nodeId">>, RootNode),
        {ok, H1NodeId} = chrme_dom:query_selector(session1, RootId, <<"h1">>),
        {ok, H1Html}   = chrme_dom:get_outer_html(session1, H1NodeId),
        true = binary:match(H1Html, <<"Example Domain">>) =/= nomatch,

        %% Alternatively double-check through JS evaluation.
        {ok, H1Obj} = chrme_runtime:evaluate(session1,
                                             <<"document.querySelector(\"h1\").innerText">>),
        H1Text = maps:get(<<"value">>, H1Obj, undefined),
        case H1Text =:= Title of
            true -> ok;
            false -> ct:fail({h1_mismatch, H1Text, Title})
        end,

        %% 7. Demonstrate Network domain – fetch https://example.com and
        %%    assert that we observe the request via the
        %%    Network.requestWillBeSent event.
        Self = self(),
        RefNetwork = chrme_network:register_request_will_be_sent_handler(session1, fun(Params) ->
            Req = maps:get(<<"request">>, Params, #{}),
            case maps:get(<<"url">>, Req, <<>> ) of
                <<"https://example.com/">> ->
                    Self ! got_example_net,
                    true;
                _ -> false
            end
        end),

        {ok, _} = chrme_network:enable(session1),

        %% Trigger a fetch from within the page context.
        _ = chrme_runtime:evaluate(session1, <<"fetch('https://example.com/')">>),

        receive
            got_example_net -> ok
        after 5000 ->
            ct:fail(network_event_timeout)
        end,

        chrme_network:unregister_request_will_be_sent_handler(session1, RefNetwork),

        %% 8. Navigate to https://example.org and wait for the navigation
        %%    to complete (signalled by Page.frameNavigated).
        {ok, _} = chrme_page:enable(session1),

        RefNav = chrme_page:register_frame_navigated_handler(session1, fun(_Params) ->
            Self ! frame_nav,
            true
        end),

        {ok, _NavInfo} = chrme_page:navigate(session1, <<"https://example.org">>),

        receive
            frame_nav -> ok
        after 5000 ->
            ct:fail(navigation_timeout)
        end,

        chrme_page:unregister_frame_navigated_handler(session1, RefNav),

        %% 9. Clean shutdown.
        ok = chrme_session:stop(Session),
        ok
    after
        chrme_launcher:stop(launch1)
    end.

%%---------------------------------------------------------------------------
%% Test case: response_body (await_response_body helper)
%%---------------------------------------------------------------------------

response_body(_Config) ->
    application:ensure_all_started(chrme),

    %% Allocate free port
    {ok, LSock} = gen_tcp:listen(0, [binary,{active,false}]),
    {ok, {_, Port}} = inet:sockname(LSock),
    ok = gen_tcp:close(LSock),

    UserDataDir = list_to_binary(io_lib:format("/tmp/chrme_ud_rb_~p", [Port])),

    LauncherOpts = #{ name => launch_rb,
                      remote_port => Port,
                      user_data_dir => UserDataDir,
                      headless => true,
                      extra_args => [ <<"--remote-allow-origins=*">> ] },

    {ok, _} = chrme_launcher:start_link(LauncherOpts),
    ok = chrme_launcher:await_start(launch_rb),

    try
        {ok, SessionMap} = chrme_session:start_link(session_rb,
                                            <<"localhost">>,
                                            Port,
                                            <<"https://example.com">>),
        ok = chrme_session:await_start(session_rb),

        Self = self(),

        %% Capture requestId via responseReceived event
        RefResp = chrme_network:register_response_received_handler(session_rb, fun(Params) ->
            RespInfo = maps:get(<<"response">>, Params, #{}),
            case maps:get(<<"url">>, RespInfo, <<>> ) of
                <<"https://example.com/">> ->
                    ReqId = maps:get(<<"requestId">>, Params, undefined),
                    Self ! {rid, ReqId},
                    true;
                _ -> false
            end
        end),

        {ok, _} = chrme_network:enable(session_rb),

        _ = chrme_runtime:evaluate(session_rb, <<"fetch('https://example.com/')">>),

        ReqId = receive
            {rid, R} -> R
        after 5000 -> ct:fail(missing_request_id)
        end,

        {ok, Body, _Encoded} = chrme_network:await_response_body(session_rb, ReqId, 5000),
        true = byte_size(Body) > 0,

        chrme_network:unregister_response_received_handler(session_rb, RefResp),

        ok = chrme_session:stop(SessionMap),
        ok
    after
        chrme_launcher:stop(launch_rb)
    end.

%%---------------------------------------------------------------------------
%% Test case: event_handler (generic Network.* handler)
%%---------------------------------------------------------------------------

event_handler(_Config) ->
    application:ensure_all_started(chrme),

    %% Allocate port for Chrome Remote Debugging
    {ok, LSock} = gen_tcp:listen(0, [binary, {active, false}]),
    {ok, {_, Port}} = inet:sockname(LSock),
    ok = gen_tcp:close(LSock),

    UserDataDir = list_to_binary(io_lib:format("/tmp/chrme_ud_eh_~p", [Port])),

    LauncherOpts = #{ name          => launch_eh,
                      remote_port   => Port,
                      user_data_dir => UserDataDir,
                      headless      => true,
                      extra_args    => [ <<"--remote-allow-origins=*">> ]
                    },
    {ok, _PidLaunch} = chrme_launcher:start_link(LauncherOpts),
    ok = chrme_launcher:await_start(launch_eh),

    try
        {ok, Session} = chrme_session:start_link(session_eh,
                                           <<"localhost">>,
                                           Port,
                                           <<"https://example.com">>),
        ok = chrme_session:await_start(session_eh),

        Self = self(),

        %% Generic Network.* handler collecting two events
        Ref = chrme_network:register_event_handler(session_eh, fun(Event) ->
            case maps:get(<<"method">>, Event, undefined) of
                <<"Network.requestWillBeSent">> ->
                    Self ! will,
                    true;
                <<"Network.responseReceived">> ->
                    Self ! resp,
                    true;
                _ -> false
            end
        end),

        {ok, _} = chrme_network:enable(session_eh),

        _ = chrme_runtime:evaluate(session_eh, <<"fetch('https://example.com/')">>),

        receive
            will -> ok
        after 5000 -> ct:fail(missing_request_will_be_sent)
        end,

        receive
            resp -> ok
        after 5000 -> ct:fail(missing_response_received)
        end,

        chrme_network:unregister_event_handler(session_eh, Ref),

        ok = chrme_session:stop(Session),
        ok
    after
        chrme_launcher:stop(launch_eh)
    end.

%%---------------------------------------------------------------------------
%% Test case: network_events
%%---------------------------------------------------------------------------

network_events(_Config) ->
    application:ensure_all_started(chrme),

    %% Pick a free debugging port for Chrome.
    {ok, LSock} = gen_tcp:listen(0, [binary, {active, false}]),
    {ok, {_, Port}} = inet:sockname(LSock),
    ok = gen_tcp:close(LSock),

    UserDataDir = list_to_binary(io_lib:format("/tmp/chrme_ud_ne_~p", [Port])),

    LauncherOpts = #{ name          => launch_ne,
                      remote_port   => Port,
                      user_data_dir => UserDataDir,
                      headless      => true,
                      extra_args    => [ <<"--remote-allow-origins=*">> ]
                    },
    {ok, _PidLaunch} = chrme_launcher:start_link(LauncherOpts),
    ok = chrme_launcher:await_start(launch_ne),

    try
        {ok, Session} = chrme_session:start_link(session_ne,
                                           <<"localhost">>,
                                           Port,
                                           <<"https://example.com">>),
        ok = chrme_session:await_start(session_ne),

        Self = self(),

        %% Individual one-off handlers for each event type.
        RefWill = chrme_network:register_request_will_be_sent_handler(session_ne, fun(_Params) ->
            Self ! will,
            true
        end),

        RefResp = chrme_network:register_response_received_handler(session_ne, fun(Params) ->
            ReqId = maps:get(<<"requestId">>, Params, undefined),
            Self ! {resp, ReqId},
            true
        end),

        RefLoad = chrme_network:register_loading_finished_handler(session_ne, fun(Params) ->
            ReqId = maps:get(<<"requestId">>, Params, undefined),
            Self ! {load, ReqId},
            true
        end),

        {ok, _} = chrme_network:enable(session_ne),

        %% Trigger a fetch inside the page.
        _ = chrme_runtime:evaluate(session_ne, <<"fetch('https://example.com/')">>),


        %% Wait for requestWillBeSent, responseReceived, loadingFinished.

        receive
            will -> ok
        after 5000 -> ct:fail(missing_request_will_be_sent)
        end,

        ReqId =
        receive
            {resp, RId} -> RId
        after 5000 -> ct:fail(missing_response_received)
        end,

        receive
            {load, ReqId} -> ok
        after 5000 -> ct:fail(missing_loading_finished)
        end,

        {ok, Body, _Encoded} = chrme_network:get_response_body(session_ne, ReqId),
        true = byte_size(Body) > 0,

        chrme_network:unregister_request_will_be_sent_handler(session_ne, RefWill),
        chrme_network:unregister_response_received_handler(session_ne, RefResp),
        chrme_network:unregister_loading_finished_handler(session_ne, RefLoad),

        ok = chrme_session:stop(Session),
        ok
    after
        chrme_launcher:stop(launch_ne)
    end.
