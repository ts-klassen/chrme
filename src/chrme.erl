-module(chrme).

-export([
        main/1
    ]).

main(Args) ->
    application:ensure_all_started(chrme),
    chrme_cli:main(Args).
