#!/usr/bin/env bash
# Throwaway probe file for #500: removes a cache directory named by $1.
set -u
CACHE_DIR=$1
rm -rf $CACHE_DIR/
count=$(ls $CACHE_DIR | wc -l)
if [ $count -gt 0 ]; then
  echo "cleanup failed" 
fi
exit 0
