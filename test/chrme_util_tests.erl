%% Simple EUnit tests for chrme_util module
-module(chrme_util_tests).
-include_lib("eunit/include/eunit.hrl").

to_list_test() ->
    ?assertEqual("hello", chrme_util:to_list(<<"hello">>)),
    ?assertEqual("world", chrme_util:to_list("world")).

to_binary_test() ->
    ?assertEqual(<<"hello">>, chrme_util:to_binary("hello")),
    ?assertEqual(<<"world">>, chrme_util:to_binary(<<"world">>)).

parse_ws_url_test() ->
    ?assertEqual({<<"example.com">>,80,<<"/path">>},
                 chrme_util:parse_ws_url("ws://example.com:80/path")).