-module(chrme_dom).
-export([get_document/1, query_selector/3, get_outer_html/2, set_attribute_value/4,
         remove_node/2, on_document_updated/2, off_document_updated/2]).

%% Get the root document node
-spec get_document(Name :: chrme_session:name()) -> {ok, map()} | {error, term()}.
get_document(Name) ->
    case chrme_cdp:call(Name, <<"DOM.getDocument">>, #{}) of
        {ok, Resp} ->
            Root = maps:get(<<"root">>, Resp),
            {ok, Root};
        Err -> Err
    end.

%% Find a child node matching selector
-spec query_selector(Name :: chrme_session:name(), NodeId :: integer(), Selector0 :: klsn:binstr()) -> {ok, integer()} | {error, term()}.
query_selector(Name, NodeId, Selector0) ->
    Sel = chrme_util:maybe_to_binary(Selector0),
    case chrme_cdp:call(Name, <<"DOM.querySelector">>, #{nodeId => NodeId, selector => Sel}) of
        {ok, Resp} ->
            {ok, maps:get(<<"nodeId">>, Resp)};
        Err -> Err
    end.

%% Get outer HTML of a node
-spec get_outer_html(Name :: chrme_session:name(), NodeId :: integer()) -> {ok, binary()} | {error, term()}.
get_outer_html(Name, NodeId) ->
    case chrme_cdp:call(Name, <<"DOM.getOuterHTML">>, #{nodeId => NodeId}) of
        {ok, Resp} ->
            {ok, maps:get(<<"outerHTML">>, Resp)};
        Err -> Err
    end.

%% Set an attribute value on an element
-spec set_attribute_value(Name :: chrme_session:name(), NodeId :: integer(), AttrName0 :: klsn:binstr(), AttrValue0 :: klsn:binstr()) -> {ok, map()} | {error, term()}.
set_attribute_value(Name, NodeId, AttrName0, AttrValue0) ->
    NameBin = chrme_util:maybe_to_binary(AttrName0),
    ValBin = chrme_util:maybe_to_binary(AttrValue0),
    chrme_cdp:call(Name, <<"DOM.setAttributeValue">>,
                   #{nodeId => NodeId, name => NameBin, value => ValBin}).

%% Remove a node from the document
-spec remove_node(Name :: chrme_session:name(), NodeId :: integer()) -> {ok, map()} | {error, term()}.
remove_node(Name, NodeId) ->
    chrme_cdp:call(Name, <<"DOM.removeNode">>, #{nodeId => NodeId}).

%% Subscribe to documentUpdated events
-spec on_document_updated(Name :: chrme_session:name(), Fun :: fun(() -> any())) -> reference().
on_document_updated(Name, Fun) ->
    Ref = make_ref(),
    CallbackName = {chrme_dom, on_document_updated, Name, Ref},
    CallbackFun = fun
        (stop) -> false;
        (Msg = #{<<"method">> := <<"DOM.documentUpdated">>, <<"params">> := Params}) ->
            Fun(Params),
            true;
        (_) -> false
    end,
    chrme_ws_apic:add_callback(Name, {CallbackName, CallbackFun}),
    Ref.

-spec off_document_updated(Name :: chrme_session:name(), Ref :: reference()) -> ok.
off_document_updated(Name, Ref) ->
    CallbackName = {chrme_dom, on_document_updated, Name, Ref},
    chrme_ws_apic:remove_callback(Name, CallbackName),
    ok.