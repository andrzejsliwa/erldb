-module(erldb).
-export([main/1]).
-export([default_connection/1]).

main(Args) ->
    io:format("~s ~s (unstable) - database managment tool by Andrzej Sliwa "
              "<andrzej.sliwa@i-tool.eu>~n~n", [?MODULE, "0.9.0"]),
    handle_args(Args).

handle_args([]) ->  handle_args(["-T"]);
handle_args(["-T"]) ->
    io:format("Usage:~n  ~s [commands...] ERLANG_ENV=development # this is default ~n~n", [?MODULE]),
    io:format("Available commands:~n~n"),
    cmd_help("create           # create database"),
    cmd_help("drop             # drop database"),
    cmd_help("schema:load      # load schema for database");
handle_args([Command]) ->
    process(Command);
handle_args([Command| Rest]) ->
    handle_args([Command]),
    handle_args(Rest).

default_connection(AppName) ->
    Config = load_config(".", AppName),
    {ok, Database} = erlang_env:get_value(database, Config),
    Opts = [{database, Database}],
    db_connect(Config, Opts).

process(Command) ->
    case filelib:is_dir("apps") of
        true  ->
            {ok, AllList} = file:list_dir("apps"),
            Dirs = lists:filter(
                     fun(Path) ->
                             filelib:is_dir(filename:join(["apps", Path]))
                     end, AllList),
            [exec(Command, load_config(filename:join(["apps", Path])), filename:join(["apps", Path])) || Path <- Dirs];
        false ->
            exec(Command, load_config("."), ".")
    end.

exec(_, [], _) -> ok;
exec("create", Config, _Path) ->
    {ok, Database} = erlang_env:get_value(database, Config),
    Opts = [{database, "postgres"}],
    {ok, Conn} = db_connect(Config, Opts),
    format_error(do_query("CREATE DATABASE " ++ Database ++ ";", Conn));
exec("drop", Config, _Path) ->
    {ok, Database} = erlang_env:get_value(database, Config),
    Opts = [{database, "postgres"}],
    {ok, Conn} = db_connect(Config, Opts),
    format_error(do_query("DROP DATABASE " ++ Database ++ ";", Conn));
exec("schema:load", Config, Path) ->
    SchemaPath = filename:join([Path, "db", "schema.sql"]),
    case filelib:is_regular(SchemaPath) of
        true ->
            {ok, Binary} = file:read_file(SchemaPath),
            transaction(fun(Conn) ->
                                ThrowError = true,
                                format_error(do_query(Binary, Conn), ThrowError)
                        end, Config);
        false ->
            io:format("missing schema file: ~s~n", [SchemaPath])
    end;
exec(Command, _, _) ->
    io:format("wrong command: ~s.~n", [Command]),
    halt(1).


transaction(Fun, Config) ->
    {ok, Database} = erlang_env:get_value(database, Config),
    Opts = [{database, Database}],
    case db_connect(Config, Opts) of
        {ok, Conn} ->
            do_query("BEGIN;", Conn),
            try
                Fun(Conn),
                do_query("COMMIT;", Conn)
            catch
                _:Reason ->
                    io:format("error: ~s~n", [Reason]),
                    do_query("ROLLBACK;", Conn),
                    pgsql:close(Conn),
                    halt(1)
            end,
            pgsql:close(Conn);
        {error, _} ->
            io:format("can't connect to db: ~p~n", [Database]),
            halt(1)
    end.



db_connect(Config) ->
    db_connect(Config, []).
db_connect(Config, Opts) ->
    {ok, Host}     = erlang_env:get_value(host    , Config),
    {ok, Password} = erlang_env:get_value(password, Config),
    {ok, User}     = erlang_env:get_value(username, Config),
    pgsql:connect(Host, User, Password, Opts).

do_query(QueryString, Conn) ->
    io:format(" >> ~s~n", [QueryString]),
    pgsql:squery(Conn, QueryString).

format_error(Data) ->
    ThrowError = false,
    format_error(Data, ThrowError).

format_error([], _ThrowError) -> ok;
format_error([Head | Rest], ThrowError) ->
    format_error(Head, ThrowError), format_error(Rest, ThrowError);

format_error({ok, _, _}, _ThrowError) ->
    io:format("done~n");
format_error({error, {error, error, _, Message, _}}, true) ->
    throw(binary_to_list(Message));
format_error({error, {error, error, _, Message, _}}, false) ->
    io:format("error: ~s~n", [binary_to_list(Message)]).

cmd_help(Message) ->
    io:format("  ~s ~s~n", [?MODULE, Message]).

load_config(Dir) ->
    Path = filename:join([Dir, "config"]),
    case filelib:wildcard("*database.config", Path) of
       [] ->
           io:format("no ~s/*database.config file...~n", [Path]),
           [];
       [FileName] ->
           FullPath = filename:join([Path, FileName]),
           {ok, Configuration} = erlang_env:load_config(FullPath),
           Configuration;
       More ->
           io:format("only one *database.config file could be in ~s!~n", [Path]),
           io:format("but are ~s!~n", [string:join(More, ", ")]),
           halt(1)
    end.

load_config(Dir, Name) ->
    FullPath = filename:join([Dir, "config", atom_to_list(Name) ++ "_database.config"]),
    {ok, Config} = erlang_env:load_config(FullPath),
    Config.
