-module(db).
-export([main/1]).

main(Args) ->
    erldb:main(Args).
