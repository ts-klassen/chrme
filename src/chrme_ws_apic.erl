-module(chrme_ws_apic).

-behaviour(gen_server).
-export([start/1, start_link/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-export([
        is_connected/1
      , last_updated_at/1
      , last_websocket_at/1
      , data_size/1
    ]).

-export_type([
        state/0
      , data/0
      , options/0
      , name/0
    ]).

-type state() :: #{
        pid               := pid()
      , stream_ref        := klsn:maybe(reference())
      , is_upgraded       := boolean()
      , last_updated_at   := klsn:maybe(klsn_flux:timestamp())
      , last_websocket_at := klsn:maybe(klsn_flux:timestamp())
      , uri               := klsn:binstr()
      , buffer            := [data()]
    }.



-type data() :: #{
    }.

-type name() :: term().
-type options() :: #{
        name := name()
      , host => klsn:binstr() % default: <<"localhost">>
      , port => 0..65535 % default: 9222
      , uri := klsn:binstr()
    }.

-spec start_link(options()) -> {ok, pid()}.
%% start without linking
-spec start(options()) -> {ok, pid()}.
start(Options) ->
    Name = maps:get(name, Options),
    gen_server:start({global, Name}, ?MODULE, Options, []).

start_link(Options) ->
    Name = maps:get(name, Options),
    gen_server:start_link({global, Name}, ?MODULE, Options, []).

%% stop the server
-spec stop(name()) -> ok.
stop(Name) ->
    gen_server:stop({global, Name}).

 -spec init(options()) -> {ok, state()}.
init(Options) ->
    Name = maps:get(name, Options),
    Host = maps:get(host, Options, <<"localhost">>),
    Port = maps:get(port, Options, 9222),
    Uri = maps:get(uri, Options),
    RetryMax = 180,
    GunOpts = #{
        supervise => true
      , retry => RetryMax
      , retry_fun => fun(Cnt, _) ->
            case Cnt of
                1 ->
                    gen_server:cast({global, Name}, too_many_retry),
                    #{retries => 0, timeout => 0};
                _ ->
                    Stage = RetryMax - Cnt,
                    Sleep = round(1000 * rand:uniform() + math:exp(Stage)),
                    timer:sleep(min(1000*60, Sleep)),
                    gen_server:cast({global, Name}, {retry, Cnt}),
                    #{retries => Cnt-1, timeout => 1000}
            end
        end
    },
process_flag(trap_exit, true),
{ok, Pid} = gun:open(Host, Port, GunOpts),
State = #{
    pid               => Pid
  , stream_ref        => none
  , is_upgraded       => false
  , last_updated_at   => none
  , last_websocket_at => none
  , uri               => Uri
  , buffer            => []
},
{ok, State}.

handle_call(data_size, _From, State) ->
    {reply, maps:size(klsn_map:get([data], State)), State};
handle_call({lookup_from_state, Path}, _From, State) ->
    {reply, klsn_map:lookup(Path, State), State}.

handle_cast({retry, _Retry}, State) ->
    io:format("retry: ~p~n", [_Retry]),
    {noreply, State};
handle_cast(too_many_retry, State) ->
    {stop, too_many_retry, State}.

handle_info({gun_upgrade, _Pid, _Ref, _, _}, State0) ->
    io:format("gun_upgrade~n"),
    Timestamp = klsn_flux:timestamp(),
    State1 = klsn_map:upsert([is_upgraded], true, State0),
    State2 = klsn_map:upsert([last_websocket_at], {value, Timestamp}, State1),
    {noreply, State2};
handle_info({gun_down, _Pid, Proto, Reason, _}, State0)
    when (Proto =:= ws orelse Proto =:= http)
      and (Reason =:= closed orelse Reason =:= normal) ->
    io:format("gun_down~n"),
    State1 = klsn_map:upsert([is_upgraded], false, State0),
    {noreply, State1};
handle_info({gun_ws, _Pid, _Ref, close}, State0) ->
    io:format("gun_ws close~n"),
    State1 = klsn_map:upsert([is_upgraded], false, State0),
    {noreply, State1};
handle_info({gun_error, _Pid, _Ref, closed}, State0) ->
    io:format("gun_error closed~n"),
    State1 = klsn_map:upsert([is_upgraded], false, State0),
    {noreply, State1};
handle_info({gun_up, Pid, http}, State0) ->
    io:format("gun_up~n"),
    Timestamp = klsn_flux:timestamp(),
    StreamRef = gun:ws_upgrade(Pid, klsn_map:get([uri], State0), []),
    State1 = klsn_map:upsert([stream_ref], {value, StreamRef}, State0),
    State2 = klsn_map:upsert([last_websocket_at], {value, Timestamp}, State1),
    {noreply, State2};
handle_info(Info, State) ->
    error_logger:info_msg("function=~p:~p/~p, line=~p~ninfo=~p~nstate=~p", [
            ?MODULE
          , ?FUNCTION_NAME
          , ?FUNCTION_ARITY
          , ?LINE
          , Info
          , klsn_map:upsert([data], 'OMMIT', State)
        ]),
    {noreply, State}.

terminate(_Reason, State) ->
    Pid = maps:get(pid, State),
    % if websocket upgraded, close it
    case klsn_map:lookup([stream_ref], State) of
        {value, Ref} -> catch gun:ws_close(Pid, Ref, 1000, <<"normal">>);
        _ -> ok
    end,
    % close the underlying connection
    catch gun:close(Pid),
    ok.


-spec lookup_from_state(name(), klsn_map:key()) -> term().
lookup_from_state(Name, Path) ->
    gen_server:call({global, Name}, {lookup_from_state, Path}).


-spec is_connected(name()) -> boolean().
is_connected(Name) ->
    klsn_maybe:get_value(lookup_from_state(Name, [is_upgraded])).

-spec last_updated_at(name()) -> klsn:maybe(klsn_flux:timestamp()).
last_updated_at(Name) ->
    klsn_maybe:get_value(lookup_from_state(Name, [last_updated_at])).

-spec last_websocket_at(name()) -> klsn:maybe(klsn_flux:timestamp()).
last_websocket_at(Name) ->
    klsn_maybe:get_value(lookup_from_state(Name, [last_websocket_at])).

-spec data_size(name()) -> non_neg_integer().
data_size(Name) ->
    gen_server:call({global, Name}, data_size).


