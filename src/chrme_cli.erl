-module(chrme_cli).

-export([main/1]).

-define(EXIT_OK, 0).
-define(EXIT_USAGE_ERROR, 1).
-define(EXIT_ERROR, 2).

main(Args) ->
    case Args of
        [] ->
            print_usage(),
            halt(?EXIT_OK);
        ["-h"] ->
            print_usage(),
            halt(?EXIT_OK);
        ["--help"] ->
            print_usage(),
            halt(?EXIT_OK);
        ["-V"] ->
            print_version(),
            halt(?EXIT_OK);
        ["--version"] ->
            print_version(),
            halt(?EXIT_OK);
        ["help" | Rest] ->
            do_help(Rest),
            halt(?EXIT_OK);
        _ ->
            case parse_args(Args) of
                {ok, Opts, CmdArgs} ->
                    dispatch(Opts, CmdArgs);
                {error, Msg} ->
                    io:format("Error: ~s~n", [Msg]),
                    print_usage(),
                    halt(?EXIT_USAGE_ERROR)
            end
    end.

do_navigate(Opts, ["--id", IdStr, UrlStr]) ->
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    Name = cli_nav,
    TargetId = list_to_binary(IdStr),
    case chrme_session:attach(Name, Host, Port, TargetId) of
        {ok, _Session} ->
            chrme_session:await_start(Name),
            _ = chrme_page:enable(Name),
            case chrme_page:navigate(Name, list_to_binary(UrlStr)) of
                {ok, Nav} ->
                    Frame = maps:get(frame_id, Nav),
                    Loader = maps:get(loader_id, Nav),
                    io:format("Navigated existing target ~ts to ~ts. FrameId=~ts loaderId=~p~n",
                              [TargetId, UrlStr, Frame, Loader]),
                    halt(?EXIT_OK);
                Err ->
                    io:format("Navigation error: ~p~n", [Err]),
                    halt(?EXIT_ERROR)
            end;
        {error, Err} ->
            io:format("Error attaching to target ~ts: ~p~n", [TargetId, Err]),
            halt(?EXIT_ERROR)
    end;
do_navigate(Opts, ["-i", IdStr, UrlStr]) ->
    do_navigate(Opts, ["--id", IdStr, UrlStr]);
do_navigate(Opts, [UrlStr]) ->
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    Name = cli_nav,
    Url = list_to_binary(UrlStr),
    case chrme_session:start(Name, Host, Port, Url) of
        {ok, _Session} ->
            chrme_session:await_start(Name),
            _ = chrme_page:enable(Name),
            case chrme_page:navigate(Name, Url) of
                {ok, Nav} ->
                    Frame = maps:get(frame_id, Nav),
                    Loader = maps:get(loader_id, Nav),
                    io:format("Navigated to ~ts. FrameId=~ts loaderId=~p~n", [Url, Frame, Loader]),
                    halt(?EXIT_OK);
                Err ->
                    io:format("Navigation error: ~p~n", [Err]),
                    halt(?EXIT_ERROR)
            end;
        {error, Err} ->
            io:format("Error starting session: ~p~n", [Err]),
            halt(?EXIT_ERROR)
    end;
do_navigate(_, _) ->
    io:format("Usage: chrme navigate <url> | --id <target-id> <url>~n", []),
    halt(?EXIT_USAGE_ERROR).
   
%% Evaluate JavaScript expression on a new or existing target
do_evaluate(Opts, ["--id", IdStr | ExprParts]) ->
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    Name = cli_eval,
    TargetId = list_to_binary(IdStr),
    case chrme_session:attach(Name, Host, Port, TargetId) of
        {ok, _Session} ->
            chrme_session:await_start(Name),
            _ = chrme_cdp:call(Name, <<"Runtime.enable">>, #{}),
            Expr = list_to_binary(string:join(ExprParts, " ")),
            case chrme_runtime:evaluate(Name, Expr) of
                {ok, Result} -> io:format("~p~n", [Result]), halt(?EXIT_OK);
                {error, Err} -> io:format("Evaluation error: ~p~n", [Err]), halt(?EXIT_ERROR)
            end;
        {error, Err} ->
            io:format("Error attaching to target ~ts: ~p~n", [TargetId, Err]),
            halt(?EXIT_ERROR)
    end;
do_evaluate(Opts, ["-i", IdStr | ExprParts]) ->
    do_evaluate(Opts, ["--id", IdStr | ExprParts]);
do_evaluate(Opts, ExprParts) when is_list(ExprParts) ->
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    Name = cli_eval,
    %% Open a blank page by default
    case chrme_session:start(Name, Host, Port, list_to_binary("about:blank")) of
        {ok, _Session} ->
            chrme_session:await_start(Name),
            _ = chrme_cdp:call(Name, <<"Runtime.enable">>, #{}),
            Expr = list_to_binary(string:join(ExprParts, " ")),
            case chrme_runtime:evaluate(Name, Expr) of
                {ok, Result} -> io:format("~p~n", [Result]), halt(?EXIT_OK);
                {error, Err} -> io:format("Evaluation error: ~p~n", [Err]), halt(?EXIT_ERROR)
            end;
        {error, Err} ->
            io:format("Error creating session: ~p~n", [Err]),
            halt(?EXIT_ERROR)
    end;
do_evaluate(_, _) ->
    io:format("Usage: chrme evaluate [--id <target-id>] <expression>~n", []),
    halt(?EXIT_USAGE_ERROR).

%% Stream all protocol events for a target (new or existing)
do_events(Opts, ["--id", IdStr]) ->
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    Name = cli_events,
    TargetId = list_to_binary(IdStr),
    case chrme_session:attach(Name, Host, Port, TargetId) of
        {ok, _Session} ->
            chrme_session:await_start(Name),
            _ = chrme_cdp:call(Name, <<"Page.enable">>, #{}),
            _ = chrme_cdp:call(Name, <<"Network.enable">>, #{}),
            _ = chrme_cdp:call(Name, <<"Runtime.enable">>, #{}),
            _ = chrme_cdp:call(Name, <<"DOM.enable">>, #{}),
            Ref = make_ref(),
            CallbackName = {cli_events, Name, Ref},
            CallbackFun = fun
                (stop) -> true;
                (Msg) ->
                    io:format("~s~n", [jsone:encode(Msg)]),
                    true
            end,
            chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
            io:format("Streaming events for target ~ts. Press Ctrl+C to quit.~n", [TargetId]),
            events_loop();
        {error, Err} ->
            io:format("Error attaching to target ~s: ~p~n", [IdStr, Err]),
            halt(?EXIT_ERROR)
    end;
do_events(Opts, ["-i", IdStr]) ->
    do_events(Opts, ["--id", IdStr]);
do_events(Opts, []) ->
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    Name = cli_events,
    case chrme_session:start(Name, Host, Port, list_to_binary("about:blank")) of
        {ok, _Session} ->
            chrme_session:await_start(Name),
            _ = chrme_cdp:call(Name, <<"Page.enable">>, #{}),
            _ = chrme_cdp:call(Name, <<"Network.enable">>, #{}),
            _ = chrme_cdp:call(Name, <<"Runtime.enable">>, #{}),
            _ = chrme_cdp:call(Name, <<"DOM.enable">>, #{}),
            Ref = make_ref(),
            CallbackName = {cli_events, Name, Ref},
            CallbackFun = fun
                (stop) -> true;
                (Msg) ->
                    io:format("~s~n", [jsone:encode(Msg)]),
                    true
            end,
            chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
            io:format("Streaming events for new target. Press Ctrl+C to quit.~n", []),
            events_loop();
    _ ->
        io:format("Usage: chrme events [--id <target-id>]~n", []),
        halt(?EXIT_USAGE_ERROR)
    end.

events_loop() ->
    receive
        _ -> events_loop()
    end.

print_usage() ->
    io:format("Usage: chrme [OPTIONS] <command> [args]~n~n", []),
    io:format("Options:~n", []),
    io:format("  -h, --help                Show this help message~n", []),
    io:format("  -V, --version             Show version~n", []),
    io:format("  -H, --host <host>         Debugging HTTP host (default \"localhost\")~n", []),
    io:format("  -P, --port <port>         Debugging HTTP port (default 9222)~n", []),
    io:format("  -e, --endpoint <ws_url>   WebSocket debugger URL (attach only)~n", []),
    io:format("  -i, --id <target-id>      Attach to an existing target ID~n", []),
    io:format("  -b, --chrome-binary <path> Path to Chrome executable (launch only)~n", []),
    io:format("  --headless                Launch Chrome in headless mode (default true)~n", []),
    io:format("  --no-headless             Launch Chrome with UI~n", []),
    io:format("  --user-data-dir <dir>     Chrome user data directory~n", []),
    io:format("  -v, --verbose             Enable verbose output~n~n", []),
    io:format("Commands:~n", []),
    io:format("  launch      Launch a new Chrome instance~n", []),
    io:format("  list        List open debugging targets~n", []),
    io:format("  new         Create a new debugging target~n", []),
    io:format("  navigate    Navigate a new page to a URL (supports --id)~n", []),
    io:format("  screenshot  Capture a screenshot (not implemented)~n", []),
    io:format("  evaluate    Evaluate JavaScript~n", []),
    io:format("  dom         Dump DOM (not implemented)~n", []),
    io:format("  pdf         Print to PDF (not implemented)~n", []),
    io:format("  events      Stream events~n", []),
    io:format("  help        Show this message or help for a specific command~n", []),
    io:format("  version     Show version~n", []).

print_version() ->
    _ = case application:load(chrme) of
            ok -> ok;
            _ -> ok
        end,
    Vsn = case application:get_key(chrme, vsn) of
        V when is_list(V); is_binary(V) -> V;
        _ -> "unknown"
    end,
    io:format("~s~n", [Vsn]).

parse_args(Args) ->
    Defaults = #{
        command => undefined,
        host => list_to_binary("localhost"),
        port => 9222,
        endpoint => undefined,
        chrome_binary => list_to_binary("/usr/bin/google-chrome"),
        headless => true,
        user_data_dir => list_to_binary("/tmp/chrme_default_user_data_dir"),
        verbose => false
    },
    parse_args_loop(Args, Defaults).

parse_args_loop([], Opts) ->
    case maps:get(command, Opts) of
        undefined -> {error, "No command specified"};
        _ -> {ok, Opts, []}
    end;
parse_args_loop([Arg|Rest], Opts) ->
    case Arg of
        "-H" ->
            case Rest of
                [Host|T] -> parse_args_loop(T, Opts#{host => list_to_binary(Host)});
                _ -> {error, "Missing argument for -H/--host"}
            end;
        "--host" ->
            case Rest of
                [Host|T] -> parse_args_loop(T, Opts#{host => list_to_binary(Host)});
                _ -> {error, "Missing argument for -H/--host"}
            end;
        "-P" ->
            case Rest of
                [P|T] ->
                    Opts1 = case catch list_to_integer(P) of
                        I when is_integer(I) -> Opts#{port => I};
                        _ -> Opts
                    end,
                    parse_args_loop(T, Opts1);
                _ -> {error, "Missing argument for -P/--port"}
            end;
        "--port" ->
            case Rest of
                [P|T] ->
                    Opts1 = case catch list_to_integer(P) of
                        I when is_integer(I) -> Opts#{port => I};
                        _ -> Opts
                    end,
                    parse_args_loop(T, Opts1);
                _ -> {error, "Missing argument for -P/--port"}
            end;
        "-e" ->
            case Rest of
                [EP|T] -> parse_args_loop(T, Opts#{endpoint => list_to_binary(EP)});
                _ -> {error, "Missing argument for -e/--endpoint"}
            end;
        "--endpoint" ->
            case Rest of
                [EP|T] -> parse_args_loop(T, Opts#{endpoint => list_to_binary(EP)});
                _ -> {error, "Missing argument for -e/--endpoint"}
            end;
        "-b" ->
            case Rest of
                [Bin|T] -> parse_args_loop(T, Opts#{chrome_binary => list_to_binary(Bin)});
                _ -> {error, "Missing argument for -b/--chrome-binary"}
            end;
        "--chrome-binary" ->
            case Rest of
                [Bin|T] -> parse_args_loop(T, Opts#{chrome_binary => list_to_binary(Bin)});
                _ -> {error, "Missing argument for -b/--chrome-binary"}
            end;
        "--headless" -> parse_args_loop(Rest, Opts#{headless => true});
        "--no-headless" -> parse_args_loop(Rest, Opts#{headless => false});
        "--user-data-dir" ->
            case Rest of
                [Dir|T] -> parse_args_loop(T, Opts#{user_data_dir => list_to_binary(Dir)});
                _ -> {error, "Missing argument for --user-data-dir"}
            end;
        "-v" -> parse_args_loop(Rest, Opts#{verbose => true});
        "--verbose" -> parse_args_loop(Rest, Opts#{verbose => true});
        Cmd when is_list(Cmd), Cmd =/= [], hd(Cmd) =:= $- ->
            {error, ["Unknown flag: ", Cmd]};
        Cmd -> {ok, Opts#{command => Cmd}, Rest}
    end.

dispatch(Opts, CmdArgs) ->
    Cmd = maps:get(command, Opts),
    CmdAtom = list_to_atom(Cmd),
    case CmdAtom of
        launch -> do_launch(Opts, CmdArgs);
        list -> do_list(Opts, CmdArgs);
        new -> do_new(Opts, CmdArgs);
        navigate -> do_navigate(Opts, CmdArgs);
        evaluate -> do_evaluate(Opts, CmdArgs);
        help -> do_help(CmdArgs), halt(?EXIT_OK);
        version -> print_version(), halt(?EXIT_OK);
        events -> do_events(Opts, CmdArgs);
        _ ->
            io:format("Unknown command: ~s~n", [Cmd]),
            print_usage(),
            halt(?EXIT_USAGE_ERROR)
    end.

do_launch(Opts, CmdArgs) ->
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    Exe = maps:get(chrome_binary, Opts),
    Headless = maps:get(headless, Opts),
    DataDir = maps:get(user_data_dir, Opts),
    Extra = case CmdArgs of
        ["--" | Rest] -> [list_to_binary(X) || X <- Rest];
        _ -> [list_to_binary(X) || X <- CmdArgs]
    end,
    Name = cli_chrome,
    LOpts = #{name => Name,
              executable => Exe,
              remote_port => Port,
              user_data_dir => DataDir,
              headless => Headless,
              extra_args => Extra},
    case chrme_launcher:start(LOpts) of
        {ok, _} -> ok;
        {error, LaunchErr} ->
            io:format("Error launching Chrome: ~p~n", [LaunchErr]),
            halt(?EXIT_ERROR)
    end,
    chrme_launcher:await_start(Name),
    case chrme_http_apic:version(Host, Port) of
        {ok, V} ->
            io:format("HTTP debug endpoint: http://~ts:~p~n", [Host, Port]),
            case maps:find(<<"webSocketDebuggerUrl">>, V) of
                {ok, Ws} -> io:format("WebSocket debugger URL: ~ts~n", [Ws]);
                error -> ok
            end;
        {error, VersionErr} ->
            io:format("Error fetching version: ~p~n", [VersionErr])
    end,
    halt(?EXIT_OK).

do_list(Opts, _Args) ->
    Host = maps:get(host, Opts),
    Port = maps:get(port, Opts),
    case chrme_http_apic:list_targets(Host, Port) of
        {ok, Targets} ->
            io:format("id\ttype\ttitle\turl\n", []),
            lists:foreach(fun(T) ->
                Id = maps:get(<<"id">>, T),
                Type = maps:get(<<"type">>, T),
                Title = maps:get(<<"title">>, T),
                Url = maps:get(<<"url">>, T),
                io:format("~ts\t~ts\t~ts\t~ts\n", [Id, Type, Title, Url])
            end, Targets),
            halt(?EXIT_OK);
        {error, Reason} ->
            io:format("Error listing targets: ~p~n", [Reason]),
            halt(?EXIT_ERROR)
    end.

do_new(Opts, CmdArgs) ->
    case CmdArgs of
        [UrlStr] ->
            Host = maps:get(host, Opts),
            Port = maps:get(port, Opts),
            Url = list_to_binary(UrlStr),
            case chrme_http_apic:new_target(Host, Port, Url) of
                {ok, M} ->
                    Id = maps:get(<<"id">>, M),
                    Ws = maps:get(<<"webSocketDebuggerUrl">>, M),
                    io:format("Target id: ~ts~n", [Id]),
                    io:format("WebSocket URL: ~ts~n", [Ws]),
                    halt(?EXIT_OK);
                {error, Reason} ->
                    io:format("Error creating target: ~p~n", [Reason]),
                    halt(?EXIT_ERROR)
            end;
        _ ->
            io:format("Usage: chrme new <url>~n", []),
            halt(?EXIT_USAGE_ERROR)
    end.

do_help([]) ->
    print_usage();
do_help([Cmd|_]) ->
    CA = list_to_atom(Cmd),
    case CA of
        launch -> io:format("Usage: chrme launch [options] [-- <extra args>]\n", []);
        list -> io:format("Usage: chrme list [options]\n", []);
        new -> io:format("Usage: chrme new <url> [options]\n", []);
        navigate -> io:format("Usage: chrme navigate <url> [options]\n", []);
        evaluate -> io:format("Usage: chrme evaluate [--id <target-id>] <expression>\n", []);
        events -> io:format("Usage: chrme events [--id <target-id>]\n", []);
        help -> io:format("Usage: chrme help [command]\n", []);
        version -> io:format("Usage: chrme version\n", []);
        _ -> io:format("Unknown command: ~s~n", [Cmd])
    end.
