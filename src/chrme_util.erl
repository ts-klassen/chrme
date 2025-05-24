%% Utility functions for chrme

-module(chrme_util).
-export([to_list/1, to_binary/1, parse_ws_url/1]).

to_list(Bin) when is_binary(Bin) ->
    binary_to_list(Bin);
to_list(List) when is_list(List) ->
    List.

to_binary(List) when is_list(List) ->
    list_to_binary(List);
to_binary(Bin) when is_binary(Bin) ->
    Bin.

parse_ws_url(WsUrl0) ->
    Ws = to_list(WsUrl0),
    case lists:prefix("ws://", Ws) of
        true ->
            PrefixLen = length("ws://"),
            parse_after_prefix(Ws, PrefixLen);
        false ->
            case lists:prefix("wss://", Ws) of
                true ->
                    PrefixLen = length("wss://"),
                    parse_after_prefix(Ws, PrefixLen);
                false ->
                    error({invalid_ws_url, Ws})
            end
    end.

parse_after_prefix(Ws, PrefixLen) ->
    {_, Rest} = lists:split(PrefixLen, Ws),
    {HostPort, Path} = lists:splitwith(fun(C) -> C =/= $/ end, Rest),
    case string:tokens(HostPort, ":") of
        [HostStr, PortStr] ->
            {list_to_binary(HostStr), list_to_integer(PortStr), list_to_binary(Path)};
        _ ->
            error({invalid_ws_hostport, HostPort})
    end.