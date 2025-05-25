-module(chrme_session_SUITE).
-include_lib("common_test/include/ct.hrl").

%% Exported callbacks --------------------------------------------------------

-export([all/0, simple/1]).

%% Test case list ------------------------------------------------------------

all() ->
    [simple].

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

        % FIXME: (codex task) await until dom is loaded.
        timer:sleep(1000), % temp

        {ok, TitleObj} = chrme_runtime:evaluate(session1, <<"document.title">>),
        Title = maps:get(<<"value">>, TitleObj, undefined),
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
        RefNetwork = chrme_network:on_request_will_be_sent(session1, fun(Params) ->
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

        chrme_network:off_request_will_be_sent(session1, RefNetwork),

        %% 8. Navigate to https://example.org and wait for the navigation
        %%    to complete (signalled by Page.frameNavigated).
        {ok, _} = chrme_page:enable(session1),

        RefNav = chrme_page:on_frame_navigated(session1, fun(_Params) ->
            Self ! frame_nav,
            true
        end),

        {ok, _NavInfo} = chrme_page:navigate(session1, <<"https://example.org">>),

        receive
            frame_nav -> ok
        after 5000 ->
            ct:fail(navigation_timeout)
        end,

        chrme_page:off_frame_navigated(session1, RefNav),

        %% 9. Clean shutdown.
        ok = chrme_session:stop(Session),
        ok
    after
        chrme_launcher:stop(launch1)
    end.
