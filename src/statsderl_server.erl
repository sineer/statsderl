-module(statsderl_server).
-include("statsderl.hrl").

-compile(inline).
-compile({inline_size, 512}).

-export([
    start_link/1
]).

-behaviour(metal).
-export([
    init/3,
    handle_msg/2,
    terminate/2
]).

-record(state, {
    header :: iodata(),
    socket :: inet:socket()
}).

%% public
-spec start_link(atom()) ->
    {ok, pid()}.

start_link(Name) ->
    metal:start_link(?SERVER, Name, undefined).

%% metal callbacks
-spec init(atom(), pid(), term()) ->
    {ok, term()} | {stop, atom()}.

init(_Name, _Parent, _Opts) ->
    BaseKey = ?ENV(?ENV_BASEKEY, ?DEFAULT_BASEKEY),
    Hostname = ?ENV(?ENV_HOSTNAME, ?DEFAULT_HOSTNAME),
    Port = ?ENV(?ENV_PORT, ?DEFAULT_PORT),

    case udp_header(Hostname, Port, BaseKey) of
        {ok, Header} ->
            case gen_udp:open(0, [{active, false}]) of
                {ok, Socket} ->
                    io:format(user, "statsd_server Got Socket! Hostname: ~p Port: ~p BaseKey: ~p",
                              [Hostname, Port, BaseKey]),
                    {ok, #state {
                        socket = Socket,
                        header = Header
                    }};
                {error, Reason} ->
                    io:format(user, "statsd_server ERROR! Reason: ~p", [Reason]),
                    {stop, Reason}
            end;
        {error, Reason} ->
            {stop, Reason}
    end.

-spec handle_msg(term(), term()) ->
    {ok, term()}.

handle_msg({cast, Packet}, #state {
        header = Header,
        socket = Socket
    } = State) ->
    io:format(user, "statsderl_server CAST! Packet: ~p State: ~p", [Packet, State]),
    erlang:port_command(Socket, [Header, Packet]),
    {ok, State};
handle_msg({inet_reply, _Socket, ok}, State) ->
    {ok, State};
handle_msg({inet_reply, _Socket, {error, Reason}}, State) ->
    statsderl_utils:error_msg("inet_reply error: ~p~n", [Reason]),
    {ok, State}.

-spec terminate(term(), term()) ->
    ok.

terminate(_Reason, _State) ->
    ok.

%% private
udp_header(Hostname, Port, BaseKey) ->
    case statsderl_utils:getaddrs(Hostname) of
        {ok, {A, B, C, D}} ->
            Header = statsderl_udp:header({A, B, C, D}, Port),
            BaseKey2 = statsderl_utils:base_key(BaseKey),
            {ok, [Header, BaseKey2]};
        {error, Reason} ->
            {error, Reason}
    end.
