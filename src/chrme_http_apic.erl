%% -*- erlang -*-

-module(chrme_http_apic).
-export([list_targets/2, version/2, new_target/3, close_target/3]).

%% Ensure httpc is started
ensure_started() ->
    case application:ensure_all_started(inets) of
        {ok, _} -> ok;
        {error, {already_started, _}} -> ok;
        Error -> Error
    end.

list_targets(Host, Port) ->
    ensure_started(),
    %% Host must be binary; Path is binary
    Url = build_url(Host, Port, <<"/json">>),
    case httpc:request(get, {Url, []}, [], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} ->
            {ok, jsone:decode(Body)};
        {ok, {{_, Code, _}, _, Body}} ->
            {error, {http_error, Code, Body}};
        {error, Reason} ->
            {error, Reason}
    end.

version(Host, Port) ->
    ensure_started(),
    Url = build_url(Host, Port, <<"/json/version">>),
    case httpc:request(get, {Url, []}, [], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} ->
            {ok, jsone:decode(Body)};
        {ok, {{_, Code, _}, _, Body}} ->
            {error, {http_error, Code, Body}};
        {error, Reason} ->
            {error, Reason}
    end.

new_target(Host, Port, Url0) ->
    ensure_started(),
    %% Host and Url0 must be binaries
    Url = cow_qs:urlencode(Url0),
    PathBin = <<"/json/new?url=", Url/binary>>,  %% build path as binary
    FullUrl = build_url(Host, Port, PathBin),
    %% new_target requires HTTP PUT, not GET
    case httpc:request(put, {FullUrl, [], "application/json", <<>>}, [], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, Body}} ->
            {ok, jsone:decode(Body)};
        {ok, {{_, Code, _}, _, Body}} ->
            {error, {http_error, Code, Body}};
        {error, Reason} ->
            {error, Reason}
    end.

close_target(Host, Port, TargetId0) ->
    ensure_started(),
    %% Host and TargetId0 must be binaries
    PathBin = <<"/json/close/", TargetId0/binary>>,
    Url = build_url(Host, Port, PathBin),
    %% close_target requires HTTP PUT
    case httpc:request(put, {Url, [], "application/json", <<>>}, [], [{body_format, binary}]) of
        {ok, {{_, 200, _}, _, _Body}} ->
            {ok, true};
        {ok, {{_, Code, _}, _, Body}} ->
            {error, {http_error, Code, Body}};
        {error, Reason} ->
            {error, Reason}
    end.

%% Build an HTTP URL; HostBin and PathBin must be binaries
build_url(HostBin, Port, PathBin) when is_binary(HostBin), is_integer(Port), is_binary(PathBin) ->
    HostList = binary_to_list(HostBin),
    PathList = binary_to_list(PathBin),
    "http://" ++ HostList ++ ":" ++ integer_to_list(Port) ++ PathList.
