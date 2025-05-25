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
    {ok, _PidLaunch} = chrme_launcher:start(LauncherOpts),
    ok = chrme_launcher:await_start(launch1),

    try

        %% 4. start a session to `https://example.com`
        {ok, Session} = chrme_session:start(session1,
                                           <<"localhost">>,
                                           Port,
                                           <<"https://example.com">>),

        % TODO: (codex task) add a simple example.
        % 5. access dom and get the title
        % 6. run javascript command to get the innerText of the first <h1>
        % 7. enable network and receive some result of fetch from example.net
        % 8. go to example.org

        %% 9. Clean shutdown.
        ok = chrme_session:stop(Session),
        ok
    after
        catch chrme_launcher:stop(launch1)
    end.
