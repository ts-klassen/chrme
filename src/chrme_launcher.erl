-module(chrme_launcher).
-behaviour(gen_server).

-export([start/1, start_link/1, await_start/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).
-export_type([
        options/0
      , state/0
      , name/0
    ]).

-type name() :: term().

-type options() :: #{
        name           := name()
      , executable     => klsn:binstr()
      , remote_port    => 0..65535
      , user_data_dir  => klsn:binstr()
      , extra_args     => [klsn:binstr()]
      , headless       => boolean()
    }.

-type state() :: #{
        port := port()
      , opts := options()
    }.

-spec start(options()) -> {ok, pid()} | {error, term()}.
start(Options) ->
    Name = maps:get(name, Options),
    gen_server:start({global, Name}, ?MODULE, Options, []).

-spec start_link(options()) -> {ok, pid()} | {error, term()}.
start_link(Options) ->
    Name = maps:get(name, Options),
    gen_server:start_link({global, Name}, ?MODULE, Options, []).

-spec await_start(name()) -> ok.
await_start(Name) ->
    % This also makes sure server exists.
    Options = gen_server:call({global, Name}, get_options),
    Host = <<"localhost">>,
    Port = maps:get(remote_port, Options),
    case chrme_http_apic:version(Host, Port) of
        {ok, _} ->
            ok;
        _Error ->
            timer:sleep(100),
            await_start(Name)
    end.

-spec stop(name()) -> ok.
stop(Name) ->
    gen_server:stop({global, Name}).

-spec init(options()) -> {ok, state()}.
init(Options0) ->
    Options = normalize_options(Options0),
    PathBin = maps:get(executable, Options),
    Path = binary_to_list(PathBin),
    RemotePort = maps:get(remote_port, Options),
    RemotePortStr = integer_to_list(RemotePort),
    DataDirBin = maps:get(user_data_dir, Options),
    DataDir = binary_to_list(DataDirBin),
    Headless = maps:get(headless, Options),
    ExtraArgsBin = maps:get(extra_args, Options),
    ExtraArgs = [binary_to_list(B) || B <- ExtraArgsBin],
    BaseArgs = [
        "--remote-debugging-port=" ++ RemotePortStr,
        "--user-data-dir=" ++ DataDir
    ],
    HeadlessArgs = case Headless of
                       true -> ["--headless"];
                       false -> []
                   end,
    CmdArgs = BaseArgs ++ HeadlessArgs ++ ExtraArgs,
    process_flag(trap_exit, true),
    Port = open_port({spawn_executable, Path}, [
        binary,
        exit_status,
        use_stdio,
        stderr_to_stdout,
        {args, CmdArgs}
    ]),
    {ok, #{port => Port, opts => Options}}.

% Internal: merge user options with defaults
-spec normalize_options(map()) -> options().
normalize_options(Options) ->
    #{
        name => maps:get(name, Options)
      , executable    => maps:get(executable, Options, <<"/usr/bin/google-chrome">>)
      , remote_port   => maps:get(remote_port, Options, 9222)
      , user_data_dir => maps:get(user_data_dir, Options, <<"/tmp/chrme_default_user_data_dir">>)
      , extra_args    => maps:get(extra_args, Options, [])
      , headless      => maps:get(headless, Options, true)
    }.

handle_call(get_options, _From, State) ->
    {reply, maps:get(opts, State), State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({Port, {data, _Data}}, State = #{port := Port}) ->
    {noreply, State};
handle_info({Port, {exit_status, Status}}, State = #{port := Port}) ->
    {stop, {chrome_exit, Status}, State};
handle_info({'EXIT', Port, Reason}, State = #{port := Port}) ->
    {stop, {port_exit, Reason}, State};
handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #{port := Port}) ->
    catch port_close(Port),
    ok.
