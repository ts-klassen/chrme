-module(chrme_page).
-export([enable/1, navigate/2, reload/1, stop_loading/1, capture_screenshot/1,
         on_frame_navigated/2, off_frame_navigated/2]).

-export_type([navigation/0]).
-type navigation() :: #{
    frame_id  := klsn:binstr(),
    loader_id := klsn:binstr() | undefined
}.

%% ------------------------------------------------------------------
%% Page domain utilities
%% ------------------------------------------------------------------

%% Enable the Page domain so that events like Page.frameNavigated will be
%% delivered. Mirrors chrme_network:enable/1.
-spec enable(Name :: chrme_session:name()) -> {ok, map()} | {error, term()}.
enable(Name) ->
    chrme_cdp:call(Name, <<"Page.enable">>, #{}).

%% Navigate the current page to a URL
-spec navigate(Name :: chrme_session:name(), Url :: klsn:binstr()) -> {ok, navigation()} | {error, term()}.
navigate(Name, Url) ->
    BinUrl = chrme_util:to_binary(Url),
    case chrme_cdp:call(Name, <<"Page.navigate">>, #{url => BinUrl}) of
        {ok, Resp} ->
            FrameId = maps:get(<<"frameId">>, Resp),
            LoaderId = maps:get(<<"loaderId">>, Resp, undefined),
            {ok, #{frame_id => FrameId, loader_id => LoaderId}};
        Err ->
            Err
    end.

-spec reload(Name :: chrme_session:name()) -> {ok, undefined} | {error, term()}.
reload(Name) ->
    case chrme_cdp:call(Name, <<"Page.reload">>, #{}) of
        {ok, _} -> {ok, undefined};
        Err -> Err
    end.

-spec stop_loading(Name :: chrme_session:name()) -> {ok, undefined} | {error, term()}.
stop_loading(Name) ->
    case chrme_cdp:call(Name, <<"Page.stopLoading">>, #{}) of
        {ok, _} -> {ok, undefined};
        Err -> Err
    end.

%% Capture page screenshot as base64
-spec capture_screenshot(Name :: chrme_session:name()) -> {ok, klsn:binstr()} | {error, term()}.
capture_screenshot(Name) ->
    case chrme_cdp:call(Name, <<"Page.captureScreenshot">>, #{}) of
        {ok, Resp} ->
            DataBin = maps:get(<<"data">>, Resp),
            {ok, DataBin};
        Err ->
            Err
    end.

%% Subscribe to frameNavigated events
-spec on_frame_navigated(Name :: chrme_session:name(), Fun :: fun((map()) -> any())) -> reference().
on_frame_navigated(Name, Fun) ->
    Ref = make_ref(),
    CallbackName = {chrme_page, on_frame_navigated, Name, Ref},
    CallbackFun = fun
        (stop) ->
            false;
        (Msg = #{<<"method">> := <<"Page.frameNavigated">>, <<"params">> := Params}) ->
            Fun(Params),
            true;
        (_) ->
            false
    end,
    chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
    Ref.

-spec off_frame_navigated(Name :: chrme_session:name(), Ref :: reference()) -> ok.
off_frame_navigated(Name, Ref) ->
    CallbackName = {chrme_page, on_frame_navigated, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.