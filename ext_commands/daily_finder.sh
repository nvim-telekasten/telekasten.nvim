#!/usr/bin/env bash

# daily_finder for telekasten.nvim 
#
# gives the plugin the ability to search for daily notes,
#     - sorted by date 
#     - creates today's note if not present, with hardcoded template

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

# function DaySuffix:
# little helper to give us st, nd, th for 1st, 2nd, 3rd, 4th, ...
DaySuffix() {
  case `date +%d` in
    1|21|31) echo "st";;
    2|22)    echo "nd";;
    3|23)    echo "rd";;
    *)       echo "th";;
  esac
}

# path to today's note
dailyfile=$the_dir/$(date --iso).md

# function CreateDaily:
# create today's daily note with hardcoded template
CreateDaily() {
    daysuffix=$(DaySuffix)
    daystr=$(LC_TIME=en_US.UTF-8 date +"%A, %B %d$daysuffix, %Y")
    datestr="title: $daystr"
    echo --- >> $dailyfile
    echo $datestr >> $dailyfile
    echo --- >> $dailyfile
}

if [ "$(basename $the_dir)" == "daily" ] ; then 
    if [ ! -f $dailyfile ] ; then 
        $(CreateDaily)
    fi
fi

find $the_dir -type f| sort -rn 
