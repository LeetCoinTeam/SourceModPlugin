# Leet SourceMod Plugin

## Development Env
Use the linux\_dev\_env.sh script to install the dependencies and build environment on Ubuntu x86\_64 14.04LTS. This install a csgo dedicated server and sourcemod sdks locally to build and run the plugin. You can start the server up by running srcds_run command in the steamcmd folder and build the plugin using ./compile\_plugin.

Make sure to add the api key to ./steamcmd/csgo/csgo/cfg/sourcemod/plugin.LeetGG.cfg

## Compilation Instructions
Move the files in the extensiondeps folder included in this repo to their respective folders in your sourcemod compilation directory. The \*.inc files are headers and the \*.dll/\*.so files are the shared object files for the third party libraries used in this plugin.

If you installed using the linux\_dev\_env script, you can run the ./compile\_plugin.sh and the plugin will be build and moved in the correct location for the local counterstrike server.

