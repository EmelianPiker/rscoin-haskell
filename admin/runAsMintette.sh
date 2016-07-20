#!/usr/bin/env bash

# first argument stays for mintette you want to launch

test -z $1 && echo "No first argument" && exit

dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

mpath=$dir/mintetteKeys/mintette$1/

stack --nix exec -- rscoin-bank --log-severity Debug add-mintette --host 127.0.0.1 --port 311$1 --key $(cat $mpath/mintette$1.pub)
stack --nix exec -- rscoin-mintette --log-severity Debug --path "$mpath/mintette-db" --sk $mpath/mintette$1.sec -p 311$1

