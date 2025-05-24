-module(chrme_ws_apic).

-behaviour(gen_server).
-export([start/1, start_link/1, stop/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-export([
        is_connected/1
      , last_updated_at/1
      , last_websocket_at/1
      , maybe_pop/1
      , send/2
      , await_send_response/2
      , await_data/2
      , add_callback/2
      , remove_callback/2
      , get_unique_id/1
    ]).

-export_type([
        state/0
      , data/0
      , options/0
      , name/0
    ]).

-type state() :: #{
        pid := pid()
      , stream_ref := klsn:maybe(reference())
      , is_upgraded := boolean()
      , last_updated_at := klsn:maybe(klsn_flux:timestamp())
      , last_websocket_at := klsn:maybe(klsn_flux:timestamp())
      , uri := klsn:binstr()
      , buffer := [data()]
      , callbacks := [callback()]
      , unique_id := -2147483648..2147483647
    }.



-type data() :: #{
    }.

-type name() :: term().

-type callback_name() :: term().
-type callback() :: {callback_name(), fun((data()|stop) -> IsDone::boolean())}.

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
{ok, Pid} = gun:open(binary_to_list(Host), Port, GunOpts),
State = #{
        pid => Pid
      , stream_ref => none
      , is_upgraded => false
      , last_updated_at => none
      , last_websocket_at => none
      , uri => Uri
      , buffer => []
      , callbacks => []
      , unique_id => -2147483648
    },
{ok, State}.

handle_call(maybe_pop, _From, State=#{buffer:=[H|T]}) ->
    {reply, {value, H}, State#{buffer:=T}};
handle_call(maybe_pop, _From, State) ->
    {reply, none, State};
handle_call(get_unique_id, _From, State=#{unique_id:=Id}) ->
    {reply, Id, State#{unique_id:=Id+1}};
handle_call({lookup_from_state, Path}, _From, State) ->
    {reply, klsn_map:lookup(Path, State), State}.

handle_cast({send, Data}, State) ->
    Pid = maps:get(pid, State),
    case klsn_map:lookup([stream_ref], State) of
        {value, StreamRef} ->
            Bin = jsone:encode(Data),
            gun:ws_send(Pid, StreamRef, {text, Bin});
        _ ->
            ok
    end,
    {noreply, State};
handle_cast({add_callback, Callback}, State=#{callbacks:=Callbacks}) ->
    {noreply, State#{callbacks:=[Callback|Callbacks]}};
handle_cast({remove_callback, CallbackName}, State=#{callbacks:=Callbacks}) ->
    FilteredCalbacks = lists:filter(fun
        ({Name, _}) when Name =:= CallbackName ->
            false;
        (_) ->
            true
    end, Callbacks),
    {noreply, State#{callbacks:=FilteredCalbacks}};
handle_cast({retry, _Retry}, State) ->
    {noreply, State};
handle_cast(too_many_retry, State) ->
    {stop, too_many_retry, State}.

handle_info({gun_upgrade, _Pid, _Ref, _, _}, State0) ->
    Timestamp = klsn_flux:timestamp(),
    State1 = klsn_map:upsert([is_upgraded], true, State0),
    State2 = klsn_map:upsert([last_websocket_at], {value, Timestamp}, State1),
    {noreply, State2};
handle_info({gun_down, _Pid, Proto, Reason, _}, State0)
    when (Proto =:= ws orelse Proto =:= http)
      and (Reason =:= closed orelse Reason =:= normal) ->
    State1 = klsn_map:upsert([is_upgraded], false, State0),
    {noreply, State1};
handle_info({gun_ws, _Pid, _Ref, close}, State0) ->
    State1 = klsn_map:upsert([is_upgraded], false, State0),
    {noreply, State1};
handle_info({gun_error, _Pid, _Ref, closed}, State0) ->
    State1 = klsn_map:upsert([is_upgraded], false, State0),
    {noreply, State1};
handle_info({gun_up, Pid, http}, State0) ->
    Timestamp = klsn_flux:timestamp(),
    StreamRef = gun:ws_upgrade(Pid, klsn_map:get([uri], State0), []),
    State1 = klsn_map:upsert([stream_ref], {value, StreamRef}, State0),
    State2 = klsn_map:upsert([last_websocket_at], {value, Timestamp}, State1),
    {noreply, State2};
handle_info({gun_ws,Pid,_Ref,{text,JSON}}, State=#{pid:=Pid}) ->
    Data = jsone:decode(JSON),
    case run_callbacks(Data, maps:get(callbacks, State, [])) of
        true ->
            {noreply, State};
        false ->
            Buffer = maps:get(buffer, State, []),
            {noreply, State#{buffer=>[Data|Buffer]}}
    end;
handle_info(Info, State) ->
    logger:info("function=~p:~p/~p, line=~p~ninfo=~p~nstate=~p", [
            ?MODULE
          , ?FUNCTION_NAME
          , ?FUNCTION_ARITY
          , ?LINE
          , Info
          , State
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

-spec maybe_pop(name()) -> klsn:maybe(data()).
maybe_pop(Name) ->
    gen_server:call({global, Name}, maybe_pop).

-spec send(name(), data()) -> ok.
send(Name, Data) ->
    gen_server:cast({global, Name}, {send, Data}).

-spec add_callback(name(), callback()) -> ok.
add_callback(Name, Callback) ->
    gen_server:cast({global, Name}, {add_callback, Callback}).

-spec remove_callback(name(), callback_name()) -> ok.
remove_callback(Name, CallbackName) ->
    gen_server:cast({global, Name}, {remove_callback, CallbackName}).

-spec get_unique_id(name()) -> integer().
get_unique_id(Name) ->
    gen_server:call({global, Name}, get_unique_id).

-spec await_send_response(name(), data()) -> data().
await_send_response(Name, Data0) ->
    NormalizedData = jsone:decode(jsone:encode(Data0)),
    Id = case klsn_map:lookup([<<"id">>], NormalizedData) of
        {value, Id0} ->
            Id0;
        none ->
            get_unique_id(Name)
    end,
    SendData = NormalizedData#{<<"id">> => Id},
    Pid = self(),
    Ref = make_ref(),
    CallbackName = {Name, await_send_response, Id, Ref},
    CallbackFunction = fun
        (stop) ->
            Pid ! {Ref, stop},
            false;
        (Data=#{<<"id">>:=RecId}) when RecId =:= Id ->
            Pid ! {Ref, data, Data},
            true;
        (_) ->
            false
    end,
    add_callback(Name, {CallbackName, CallbackFunction}),
    send(Name, SendData),
    receive
        {Ref, stop} ->
            error(noproc);
        {Ref, data, Data} ->
            remove_callback(Name, CallbackName),
            Data
    end.

-spec await_data(name(), fun((data())->boolean())) -> data().
await_data(Name, Fun) ->
    Pid = self(),
    Ref = make_ref(),
    CallbackName = {Name, await_data, Ref},
    CallbackFunction = fun
        (stop) ->
            Pid ! {Ref, stop},
            false;
        (Data) ->
            case Fun(Data) of
                true ->
                    Pid ! {Ref, data, Data},
                    true;
                Other ->
                    Other
            end
    end,
    add_callback(Name, {CallbackName, CallbackFunction}),
    receive
        {Ref, stop} ->
            error(noproc);
        {Ref, data, Data} ->
            remove_callback(Name, CallbackName),
            Data
    end.

-spec run_callbacks(data(), [callback()]) -> boolean().
run_callbacks(_Data, []) ->
    false;
run_callbacks(Data, [{CName,CFun}|T]) ->
    try CFun(Data) of
        true ->
            case Data of
                stop ->
                    run_callbacks(Data, T);
                _ ->
                    true
            end;
        false ->
            run_callbacks(Data, T);
        Other ->
            logger:error("Unexpected ~p callback return of ~p. Boolean expected.~n~p~ncalled as ~p(~p)~n", [?MODULE, CName, Other, CFun, Data]),
            run_callbacks(Data, T)
    catch Class:Reason:Stack ->
        logger:error("Exception raised on ~p callback ~p.~n~p~ncalled as ~p(~p)~n", [?MODULE, CName, {Class, Reason, Stack}, CFun, Data]),
        run_callbacks(Data, T)
    end.

