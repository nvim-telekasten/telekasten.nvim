#!/usr/bin/env bash

# daily_finder for telekasten.nvim 
#
# actually, this is now the standard finder in telekasten

if [ "$1" == "check" ] ; then 
    echo OK
    exit 0
fi

# if called by the plugin, no args are provided, and the current working
# directory is set instead
if [ "$1" == "" ] ; then 
    the_dir=$(pwd)
else
    the_dir=$1
fi

# sort reversed numerical
find $the_dir -type f | sort -rn 
