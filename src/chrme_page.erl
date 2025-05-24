-module(chrme_page).
-export([navigate/2, reload/1, stop_loading/1, capture_screenshot/1,
         on_frame_navigated/2, off_frame_navigated/2]).

%% Navigate the current page to a URL
navigate(Name, Url) ->
    BinUrl = chrme_util:maybe_to_binary(Url),
    case chrme_cdp:call(Name, <<"Page.navigate">>, #{url => BinUrl}) of
        {ok, Resp} ->
            FrameId = maps:get(<<"frameId">>, Resp),
            LoaderId = maps:get(<<"loaderId">>, Resp, undefined),
            {ok, #{frame_id => FrameId, loader_id => LoaderId}};
        Err ->
            Err
    end.

reload(Name) ->
    case chrme_cdp:call(Name, <<"Page.reload">>, #{}) of
        {ok, _} -> {ok, undefined};
        Err -> Err
    end.

stop_loading(Name) ->
    case chrme_cdp:call(Name, <<"Page.stopLoading">>, #{}) of
        {ok, _} -> {ok, undefined};
        Err -> Err
    end.

%% Capture page screenshot as base64
capture_screenshot(Name) ->
    case chrme_cdp:call(Name, <<"Page.captureScreenshot">>, #{}) of
        {ok, Resp} ->
            DataBin = maps:get(<<"data">>, Resp),
            {ok, DataBin};
        Err ->
            Err
    end.

%% Subscribe to frameNavigated events
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

off_frame_navigated(Name, Ref) ->
    CallbackName = {chrme_page, on_frame_navigated, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.