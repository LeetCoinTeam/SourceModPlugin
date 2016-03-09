#!/bin/bash
###
# compile_extension.sh
## 
rm -r alliedmodders/sourcemod/public/leet_ext
cp -r ./leet_ext alliedmodders/sourcemod/public/
cd alliedmodders/sourcemod/public/leet_ext/build
rm -rf ./*
python ../configure.py
ambuild
cd ../../../../../
cp alliedmodders/sourcemod/public/leet_ext/build/Leet.ext.2.csgo/Leet.ext.2.csgo.so steamcmd/csgo/csgo/addons/sourcemod/extensions/
cp ./leet_ext/Leet.inc alliedmodders/sourcemod/build/package/addons/sourcemod/scripting/include/
