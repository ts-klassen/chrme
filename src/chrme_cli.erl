-module(chrme_cli).

-export([
        main/1
    ]).

main(_Args) ->
    BinStr = klsn_io:get_line(<<"Enter a text:\n> ">>),
    klsn_io:format("This is how you print string: ~ts~n", [BinStr]).
