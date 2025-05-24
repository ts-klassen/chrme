-module(chrme_session_SUITE).
-include_lib("common_test/include/ct.hrl").

%% Export the suite callback and test cases
-export([
        all/0
      , simple/1
    ]).

%% Define the test suite with all/0
all() ->
    [
        simple
    ].

%% Just make sure there is no error

simple(_Config) ->
    % TODO: (codex task) add a simple example.
    % 1. make a random port number from ephemeral port.
    % 2. start_link a launcher with that port number.
    % 3. start a session to `https://example.com`
    % 4. access dom and get the title
    % 5. run javascript command to get the innerText of the first <h1>
    % 6. enable network and receive some result of fetch from example.net
    % 7. go to example.org
    % 8. close session
    ok.

