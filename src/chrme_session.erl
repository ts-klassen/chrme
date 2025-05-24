-module(chrme_session).
-export([start/4, stop/1]).

-export_type([name/0, session/0]).                                          
-type name() :: chrme_ws_apic:name().                                       
-type session() :: #{                                                       
    name       := name(),                                                   
    host       := klsn:binstr(),                                            
    port       := integer(),                                                
    target_id  := klsn:binstr()                                             
}.

%% Start a new Chrome debugging session by creating a new target and opening a WebSocket
start(Name, Host, Port, Url) ->
    case chrme_http_apic:new_target(Host, Port, Url) of
        {ok, TargetMap} ->
            Id = maps:get(<<"id">>, TargetMap),
            WsUrl = maps:get(<<"webSocketDebuggerUrl">>, TargetMap),
            {WsHost, WsPort, WsPath} = chrme_util:parse_ws_url(WsUrl),
            WsOpts = #{name => Name, host => WsHost, port => WsPort, uri => WsPath},
            {ok, _Pid} = chrme_ws_apic:start(WsOpts),
            {ok, #{name => Name, host => WsHost, port => WsPort, target_id => Id}};
        Error ->
            Error
    end.

%% Stop the debugging session, close WebSocket and target
stop(#{name := Name, host := Host, port := Port, target_id := Id}) ->
    _ = chrme_ws_apic:stop(Name),
    _ = chrme_http_apic:close_target(Host, Port, Id),
    ok.
