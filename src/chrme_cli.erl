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

do_navigate(Opts, CmdArgs) ->
    case CmdArgs of
        [UrlStr] ->
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
        _ ->
            io:format("Usage: chrme navigate <url>~n", []),
            halt(?EXIT_USAGE_ERROR)
    end.

print_usage() ->
    Usage = "\
Usage: chrme <command> [options]\n\
\n\
Commands:\n\
  launch      Launch a new Chrome instance\n\
  list        List open debugging targets\n\
  new         Create a new debugging target\n\
  navigate    Navigate a new page to a URL (not implemented)\n\
  screenshot  Capture a screenshot (not implemented)\n\
  evaluate    Evaluate JavaScript (not implemented)\n\
  dom         Dump DOM (not implemented)\n\
  pdf         Print to PDF (not implemented)\n\
  events      Stream events (not implemented)\n\
  help        Show this message or help for a specific command\n\
  version     Show version\n\
",
    io:format("~s", [Usage]).

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
        help -> do_help(CmdArgs), halt(?EXIT_OK);
        version -> print_version(), halt(?EXIT_OK);
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
        help -> io:format("Usage: chrme help [command]\n", []);
        version -> io:format("Usage: chrme version\n", []);
        _ -> io:format("Unknown command: ~s~n", [Cmd])
    end.