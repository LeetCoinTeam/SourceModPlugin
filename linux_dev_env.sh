#!/bin/bash
# Check if root for apt-get, exit if not
if [ "$(id -u)" != "0" ]; then
        echo "Sorry, you are not root."
        exit 1
fi
# 32 bit libraries for 64 bit servers
sudo apt-get install lib32gcc1 git gcc g++ gcc-multilib g++-multilib lib32ncurses5 lib32bz2-1.0 lib32z1 lib32z1-dev
 libc6-dev-i386 libc6-i386 lib32stdc++-4.8-dev
# Make steamcmd dir
mkdir steamcmd
cd steamcmd
# Download steamcmd and extract it
wget https://steamcdn-a.akamaihd.net/client/installer/steamcmd_linux.tar.gz
tar -xvf steamcmd_linux.tar.gz
rm steamcmd_linux.tar.gz
# Install the counterstrike source dedicated server
./steamcmd.sh +login anonymous +force_install_dir ./csgo +app_update 740 validate +quit

# ambuild, the custom builder for sourcemod
cd ..
git clone https://github.com/alliedmodders/ambuild
cd ambuild
sudo python setup.py install

# Download sourcemod SDKs
cd ..
rm -rf ambuild
mkdir alliedmodders
cd alliedmodders
git clone --recursive https://github.com/alliedmodders/sourcemod
bash sourcemod/tools/checkout-deps.sh 

# Build sourcemod
cd sourcemod
mkdir build
cd build
python ../configure.py
ambuild

# Install metamod
cd ../../../
wget https://www.metamodsource.net/downloads/mmsource-1.10.6-linux.tar.gz/19
mv 19 mmsource.tar.gz
tar -xvf mmsource.tar.gz
mv addons steamcmd/csgo/csgo/
rm -rf addons
rm mmsource.tar.gz

# Install sourcemod
wget https://www.sourcemod.net/smdrop/1.7/sourcemod-1.7.3-git5298-linux.tar.gz
tar -xvf sourcemod-1.7.3-git5298-linux.tar.gz
mv addons/metamod/* steamcmd/csgo/csgo/addons/metamod/
mv addons/sourcemod steamcmd/csgo/csgo/addons/
mv cfg/* steamcmd/csgo/csgo/cfg/
rm -rf cfg addons sourcemod-1.7.3-git5298-linux.tar.gz

# Install leet plugin to the compile directory and the csgo server
wget http://www.andrewjdonley.com/leetplugin.tar.gz
tar -xvf leetplugin.tar.gz
cp leetplugin/scripting/include/* steamcmd/csgo/csgo/addons/sourcemod/scripting/include/
cp leetplugin/scripting/LeetGG.sp steamcmd/csgo/csgo/addons/sourcemod/scripting/LeetGG.sp
cp leetplugin/plugins/LeetGG.smx steamcmd/csgo/csgo/addons/sourcemod/plugins/LeetGG.smx
cp leetplugin/extensions/* steamcmd/csgo/csgo/addons/sourcemod/extensions/
cp leetplugin/scripting/include/* alliedmodders/sourcemod/build/package/addons/sourcemod/scripting/include/
cp leetplugin/scripting/LeetGG.sp alliedmodders/sourcemod/build/package/addons/sourcemod/scripting/LeetGG.sp
cp leetplugin/plugins/LeetGG.smx alliedmodders/sourcemod/build/package/addons/sourcemod/plugins/LeetGG.smx
cp leetplugin/extensions/* alliedmodders/sourcemod/build/package/addons/sourcemod/extensions/

cp leetplugin/scripting/LeetGG.sp ./LeetGG.sp

rm -rf leetplugin.tar.gz leetplugin
# Should probably use variables here...
printf "#!/bin/bash\ncp LeetGG.sp alliedmodders/sourcemod/build/package/addons/sourcemod/scripting/\nalliedmodders/sourcemod/build/package/addons/sourcemod/scripting/compile.sh LeetGG.sp\ncp alliedmodders/sourcemod/build/package/addons/sourcemod/scripting/compiled/LeetGG.smx steamcmd/csgo/csgo/addons/sourcemod/plugins/LeetGG.smx\nprintf \"Copied plugin to csgo server plugin directory.\n\"\n" > compile_plugin.sh

printf "\nUse \'./compile_plugin.sh\' to compile the LeetGG.sp plugin in this working directory.\n"

sudo chmod 755 ./compile_plugin.sh
sudo chown -R $SUDO_USER:$SUDO_USER ./
