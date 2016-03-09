#!/bin/bash
###
# compile_extension.sh
## 

cp -r ./leet_ext alliedmodders/sourcemod/public/
cd alliedmodders/sourcemod/public/leet_ext
ambuild
cd ../../../../
