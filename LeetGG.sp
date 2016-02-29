#pragma semicolon 1

#include <string>
#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <smjansson>
#include <Leet>

//Uncomment to enable debug mode.
#define DEBUG

#define PLUGIN_NAME		"Leet GG"
#define PLUGIN_AUTHOR	"Leetcoin Team"
#define PLUGIN_DES		"The official Leet.gg plugin for Sourcemod. This plugin takes advantage of our native API."
#define PLUGIN_VERSION	"1.0.0"
#define PLUGIN_URL		"https://www.leet.gg/"

//#define API_URL			"api-dot-1337coin.appspot.com"
#define API_URL			"http://apitest-dot-1337coin.appspot.com"
#define API_URL_BLEED	"apitest-dot-1337coin.appspot.com"
#define TEST_URL		"https://www.leet.gg/server/view/agpzfjEzMzdjb2luchMLEgZTZXJ2ZXIYgICA9MD-_gsM"

#define API_URL_GET_SERVER_INFO		"/api/get_server_info"
#define API_URL_ACTIVATE_PLAYER		"/api/activate_player"
#define API_URL_PUT_MATCH_RESULTS	"/api/put_match_results"
#define API_URL_ISSUE_AWARD			"/api/issue_award"
#define API_URL_DEACTIVATE_PLAYER	"/api/deactivate_player"

Handle hConVars[3];
bool cv_bStatus; 
char cv_sAPIKey[256];
char cv_sServerSecret[256];

bool bServerSetup;

//On Server Start
int g_minimumBTCHold;
bool g_no_death_penalty;
bool g_allow_non_authorized_players;
int g_admissionFee;
float g_serverRakeBTCPercentage;
char g_api_version[256];
int g_incrementBTC;
float g_leetcoinRakePercentage;
bool g_authorization;

//On Client Connect
int g_player_btchold[MAXPLAYERS + 1];
char g_player_name[MAXPLAYERS + 1][512];
char g_player_platformid[MAXPLAYERS + 1][64];
char g_player_key[MAXPLAYERS + 1][128];
bool g_player_previously_active[MAXPLAYERS + 1];
int g_player_rank[MAXPLAYERS + 1];
bool g_player_authorized[MAXPLAYERS + 1];
char g_default_currency_conversion[MAXPLAYERS + 1][64];
char g_default_currency_display[MAXPLAYERS + 1][32];
bool g_authorization_client[MAXPLAYERS + 1];

int kill_reward;
int rake;
char iCommunityID[MAXPLAYERS + 1][32];
int iClientRank[MAXPLAYERS + 1];
int iStatsKills[MAXPLAYERS + 1];
int iStatsDeaths[MAXPLAYERS + 1];

public Plugin myinfo = 
{
	name = PLUGIN_NAME, 
	author = PLUGIN_AUTHOR, 
	description = PLUGIN_DES, 
	version = PLUGIN_VERSION, 
	url = PLUGIN_URL
};

public void OnPluginStart()
{
	CreateConVar("leet_gg_version", PLUGIN_VERSION, PLUGIN_DES, FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
	
	hConVars[0] = CreateConVar("sm_leetgg_status", "1", "Status of the plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	hConVars[1] = CreateConVar("sm_leetgg_api", "", "Server API key to use.", FCVAR_PROTECTED);
	hConVars[2] = CreateConVar("sm_leetgg_sever_secret", "", "Server Secret to use", FCVAR_PROTECTED);
	
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	HookEvent("round_end", OnRoundEnd);
	
	RegAdminCmd("sm_chicken", OnSpawnChicken, ADMFLAG_ROOT, "Spawn a chicken where youre looking.");
	
	//CreateTimer(30.0, SubmitPlayerInformation, _, TIMER_REPEAT);

	HookEntityOutput("chicken", "OnBreak", OnChickenKill);
	
	AutoExecConfig();
}

public Action OnRoundEnd(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			PrintToChat(i, "Your current balance is: %i satoshi.", g_player_btchold[i]);
	return Plugin_Continue;
}

public void OnConfigsExecuted()
{
	cv_bStatus = GetConVarBool(hConVars[0]);
	GetConVarString(hConVars[1], cv_sAPIKey, 256);
	GetConVarString(hConVars[2], cv_sServerSecret, 256);
	
	if (!cv_bStatus)
	{
		bServerSetup = false;
		return;
	}
	
	if (strlen(cv_sAPIKey) == 0 || strlen(cv_sServerSecret) == 0)
	{
		Leet_Log("Error retrieving server information, API key or Server secret is missing.");
		Leet_Log("Api Key: %s", cv_sAPIKey);
		Leet_Log("Server Secret: %s", cv_sServerSecret);
		bServerSetup = false;
		return;
	}
	
	Leet_Log("Requesting server information...");
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", API_URL, API_URL_GET_SERVER_INFO);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	char params[4096];
	Format(params, sizeof(params), "nonce=%s", sTime);

	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	char sHash[2048];
	digest_string_with_key(cv_sServerSecret, params, sHash, 2048);
	
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-type", "application/x-www-form-urlencoded");
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Key", cv_sAPIKey);
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Sign", sHash);
	SteamWorks_SetHTTPCallbacks(hRequest, OnPullingServerInfo);
	SteamWorks_SendHTTPRequest(hRequest);
}

public int OnPullingServerInfo(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
	if (bFailure || !bRequestSuccessful)
	{
		bServerSetup = false;
		Leet_Log("Error retrieving server information. Error code: %i", view_as<int>(eStatusCode));
		#if defined DEBUG
		Leet_DebugLog("Pulling server information failure:\n-bFailure = %s\n-bRequestSuccessful = %s\n-eStatusCode = %i", bFailure ? "True" : "False", bRequestSuccessful ? "True" : "False", view_as<int>(eStatusCode));
		Leet_Log("Request %s", hRequest);
		#endif
		return;
	}
	
	int size = 0;
	SteamWorks_GetHTTPResponseBodySize(hRequest, size);
	
	char[] sBuffer = new char[size];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBuffer, size);
	Leet_Log("Json string: %s ",sBuffer);
	
	Handle hJSON = json_load(sBuffer);
	g_minimumBTCHold = json_object_get_int(hJSON, "minimumBTCHold");
	g_no_death_penalty = json_object_get_bool(hJSON, "no_death_penalty");
	g_allow_non_authorized_players = json_object_get_bool(hJSON, "allow_non_authorized_players");
	g_admissionFee = json_object_get_int(hJSON, "admissionFee");
	g_serverRakeBTCPercentage = json_object_get_float(hJSON, "serverRakeBTCPercentage");
	json_object_get_string(hJSON, "api_version", g_api_version, sizeof(g_api_version));
	g_incrementBTC = json_object_get_int(hJSON, "incrementBTC");
	g_leetcoinRakePercentage = json_object_get_float(hJSON, "leetcoinRakePercentage");
	g_authorization = json_object_get_bool(hJSON, "authorization");
	
	#if defined DEBUG
	Leet_DebugLog("Server information pulled:\n-minimumBTCHold = %i\n-no_death_penalty = %s\n-allow_non_authorized_players = %s\n-admissionFee = %i\n-serverRakeBTCPercentage = %f\n-api_version = %s\n-incrementBTC = %i\n-leetcoinRakePercentage = %f\n-authorization = %s", g_minimumBTCHold, g_no_death_penalty ? "True" : "False", g_allow_non_authorized_players ? "True" : "False", g_admissionFee, g_serverRakeBTCPercentage, g_api_version, g_incrementBTC, g_leetcoinRakePercentage, g_authorization ? "True" : "False");
	#endif
	
	float rake_per = g_serverRakeBTCPercentage + g_leetcoinRakePercentage;
	rake = RoundToCeil(g_incrementBTC * rake_per);
	kill_reward = RoundToCeil(g_incrementBTC - (g_incrementBTC * rake_per));
	
	Leet_Log("Server information retrieval successful.");
	bServerSetup = true;
}

public void OnClientAuthorized(int client, const char[] sAuth)
{
	if (!cv_bStatus || !bServerSetup)
	{
		return;
	}
	
	iCommunityID[client] = "";
	iClientRank[client] = 0;
	iStatsKills[client] = 0;
	iStatsDeaths[client] = 0;
	
	char sCommunityID[128];
	GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID));
	
	Leet_Log("Community ID one: %s", sCommunityID);
	strcopy(iCommunityID[client], 32, sCommunityID);
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", API_URL, API_URL_ACTIVATE_PLAYER);

	Leet_Log("On client authorized.");
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	char sAuthID[128];
	GetClientAuthId(client, AuthId_SteamID64, sAuthID, sizeof(sAuthID));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "platformid", sAuthID);

	char params[2048];
	Format(params, sizeof(params), "nonce=%s&platformid=%s", sTime, sAuthID); 
	
	char sHash[2048];
	digest_string_with_key(cv_sServerSecret, params, sHash, 2048);	
	
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-type", "application/x-www-form-urlencoded");
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Key", cv_sAPIKey);
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Sign", sHash);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	
	SteamWorks_SetHTTPCallbacks(hRequest, OnPullingClientInfo);
	SteamWorks_SendHTTPRequest(hRequest);
}

public int OnPullingClientInfo(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1)
{
	int client = GetClientOfUserId(data1);
	
	if (client < 1)
	{
		Leet_Log("Error retrieving client information, client index is invalid.");
		return;
	}
	
	if (bFailure || !bRequestSuccessful)
	{
		Leet_Log("Error retrieving client information for %L. Error code: %i", client, view_as<int>(eStatusCode));
		#if defined DEBUG
		Leet_DebugLog("Pulling client information failure for %L:\n-bFailure = %s\n-bRequestSuccessful = %s\n-eStatusCode = %i", client, bFailure ? "True" : "False", bRequestSuccessful ? "True" : "False", view_as<int>(eStatusCode));
		#endif
		return;
	}
	
	int size = 0;
	SteamWorks_GetHTTPResponseBodySize(hRequest, size);
	
	char[] sBuffer = new char[size];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBuffer, size);
	
	Handle hJSON = json_load(sBuffer);
	g_player_btchold[client] = json_object_get_int(hJSON, "player_btchold");
	json_object_get_string(hJSON, "player_name", g_player_name[client], 512);
	json_object_get_string(hJSON, "player_platformid", g_player_platformid[client], 64);
	json_object_get_string(hJSON, "player_key", g_player_key[client], 128);
	g_player_previously_active[client] = json_object_get_bool(hJSON, "player_previously_active");
	g_player_rank[client] = json_object_get_int(hJSON, "player_rank");
	g_player_authorized[client] = json_object_get_bool(hJSON, "player_authorized");
	//json_object_get_string(hJSON, "g_default_currency_conversion", g_default_currency_conversion[client], 64);
	json_object_get_string(hJSON, "default_currency_display", g_default_currency_display[client], 32);
	g_authorization_client[client] = json_object_get_bool(hJSON, "authorization");
	
	if (g_authorization && !g_player_authorized[client])
	{
		KickClient(client, "You are not authorized to join this server.");
	}
	
	#if defined DEBUG
	Leet_DebugLog("Client information pulled:\n-player_btchold = %i\n-player_name = %s\n-player_platformid = %s\n-player_key = %s\n-player_previously_active = %s\n-player_rank = %i\n-player_authorized = %s\n-g_default_currency_conversion = %s\n-default_currency_display = %s\n-authorization = %s", g_player_btchold[client], g_player_name[client], g_player_platformid[client], g_player_key[client], g_player_previously_active[client] ? "True" : "False", g_player_rank[client], g_player_authorized[client] ? "True" : "False", g_default_currency_conversion[client], g_default_currency_display[client], g_authorization_client[client] ? "True" : "False");
	#endif
	
	Leet_Log("Client '%N' information retrieval successful.", client);
}

public void OnClientDisconnect(int client)
{

	Leet_Log("On client disconnect.");

	if (!cv_bStatus || !bServerSetup)
	{
		return;
	}
	
	iCommunityID[client] = "";
	iClientRank[client] = 0;
	iStatsKills[client] = 0;
	iStatsDeaths[client] = 0;
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", API_URL, API_URL_DEACTIVATE_PLAYER);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	char sAuthID[128];
	GetClientAuthId(client, AuthId_SteamID64, sAuthID, sizeof(sAuthID));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "platformid", sAuthID);

	char params[4096];
	Format(params, sizeof(params), "nonce=%s&platformid=%s", sTime, sAuthID); 
	
	char sHash[2048];
	digest_string_with_key(cv_sServerSecret, params, sHash, 2048);	
	
	
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-type", "application/x-www-form-urlencoded");
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Key", cv_sAPIKey);
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Sign", sHash);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	
	SteamWorks_SetHTTPCallbacks(hRequest, OnDeactivatingPlayer);
	SteamWorks_SendHTTPRequest(hRequest);
}

public int OnDeactivatingPlayer(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1)
{
	int client = GetClientOfUserId(data1);
	
	if (client < 1)
	{
		Leet_Log("Error deactivating client, client index is invalid.");
		return;
	}
	
	if (bFailure || !bRequestSuccessful)
	{
		Leet_Log("Error deactivating client for %L. Error code: %i", client, view_as<int>(eStatusCode));
		#if defined DEBUG
		Leet_DebugLog("Pulling client deactivation failure for %L:\n-bFailure = %s\n-bRequestSuccessful = %s\n-eStatusCode = %i", client, bFailure ? "True" : "False", bRequestSuccessful ? "True" : "False", view_as<int>(eStatusCode));
		#endif
		return;
	}
	
	bool g_player_previously_active2;
	bool g_player_authorized2;
	char g_player_key2[256];
	bool g_authorization2;
	
	int size = 0;
	SteamWorks_GetHTTPResponseBodySize(hRequest, size);
	
	char[] sBuffer = new char[size];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBuffer, size);
	
	Handle hJSON = json_load(sBuffer);
	g_player_previously_active2 = json_object_get_bool(hJSON, "player_previously_active");
	g_player_authorized2 = json_object_get_bool(hJSON, "player_authorized");
	json_object_get_string(hJSON, "player_key", g_player_key2, sizeof(g_player_key2));
	g_authorization2 = json_object_get_bool(hJSON, "authorization");
	
	#if defined DEBUG
	Leet_DebugLog("Client deactivation data:\n-player_previously_active = %s\n-player_authorized = %s\n-player_key = %s\n-authorization = %s", g_player_previously_active2 ? "True" : "False", g_player_authorized2 ? "True" : "False", g_player_key2, g_authorization2 ? "True" : "False");
	#endif
	
	Leet_Log("Client '%N' deactivation successful.", client);
}

public void OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if (!cv_bStatus || !bServerSetup)
		return;
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	// TODO: Need to check if it was an entity that killed the player
	if (client != attacker)
	{
		if (g_player_authorized[client] && g_player_authorized[attacker])
		{
			g_player_btchold[attacker] += kill_reward;
			Leet_Log("kill_reward : %i\n", kill_reward);
			
			if (!g_no_death_penalty) {
				g_player_btchold[client] -= (kill_reward + rake);
				Leet_Log("Rake: %f\n", rake);
			}
			
			CalculateEloRank(attacker, client, false);
			
			if (g_player_btchold[client] < g_minimumBTCHold)
				KickClient(client, "Your balance is too low to continue playing.  Go to leet.gg to add more btc to your server hold.");
			
			PrintToChatAll("%N earned: %i Satoshi for killing %N", attacker, kill_reward, client);
			SubmitKill(attacker, client);
			
		}
		
		iStatsKills[attacker]++;
		iStatsDeaths[client]++;
	}
	
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (strcmp(sArgs, "balance", false) == 0 || strcmp(sArgs, "!balance", false) == 0)
	{
		PrintToChat(client, "Your current balance is: %i satoshi.", g_player_btchold[client]);
 		return Plugin_Handled;
	}
	return Plugin_Continue;
}

public Action SubmitPlayerInformation(Handle timer, any data)
{
	if (!cv_bStatus || !bServerSetup)
	{
		return Plugin_Continue;
	}
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", API_URL, API_URL_PUT_MATCH_RESULTS);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	char sMapname[64];
	GetCurrentMap(sMapname, sizeof(sMapname));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "map_title", sMapname);
	
	Handle hPlayerArray = json_array();
	
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			Handle hSingle = json_object(); char sBuffer[2048];
			
			//PlatformID
			Format(sBuffer, sizeof(sBuffer), "%s", iCommunityID[i]);
			json_object_set_new(hSingle, "platformID", json_string(sBuffer));
			
			//Kills
			Format(sBuffer, sizeof(sBuffer), "%i", iStatsKills[i]);
			json_object_set_new(hSingle, "kills", json_string(sBuffer));
			
			//Deaths
			Format(sBuffer, sizeof(sBuffer), "%i", iStatsDeaths[i]);
			json_object_set_new(hSingle, "deaths", json_string(sBuffer));
			
			//Name
			GetClientName(i, sBuffer, sizeof(sBuffer));
			json_object_set_new(hSingle, "name", json_string(sBuffer));
			
			//Rank
			Format(sBuffer, sizeof(sBuffer), "%i", iClientRank[i]);
			json_object_set_new(hSingle, "rank", json_string(sBuffer));
			
			//Weapon
			new String:sWeaponName[64];
			GetClientWeapon(i, sWeaponName, sizeof(sWeaponName));
			json_object_set_new(hSingle, "weapon", json_string(sWeaponName));

			json_array_append(hPlayerArray, hSingle);
		}
	}
	
	char sJSONList[10000];
	json_dump(hPlayerArray, sJSONList, sizeof(sJSONList));

	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "player_dict_list", sJSONList);

	char json_escaped[10000];
	int output_len = url_escape(json_escaped, sizeof(json_escaped), sJSONList);

	char params[10000];
	Format(params, sizeof(params), "nonce=%s&map_title=%s&player_dict_list=", sTime, sMapname); 
	int len = output_len + strlen(params);

	append_string(params, strlen(params), json_escaped, output_len);

	char sHash[2048];
	digest_string_with_key_length(cv_sServerSecret, params, sHash, 2048, len);	

	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-type", "application/x-www-form-urlencoded");
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Key", cv_sAPIKey);
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Sign", sHash);
	
	SteamWorks_SetHTTPCallbacks(hRequest, OnSubmittingMatchResults);
	SteamWorks_SendHTTPRequest(hRequest);
	
	return Plugin_Continue;
}

public Action SubmitKill(int killer, int victim)
{
	if (!cv_bStatus || !bServerSetup)
	{
		return Plugin_Continue;
	}
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", API_URL, API_URL_PUT_MATCH_RESULTS);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	char sMapname[64];
	GetCurrentMap(sMapname, sizeof(sMapname));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "map_title", sMapname);
	
	Handle hPlayerArray = json_array();
	
	if (IsClientInGame(killer) && !IsFakeClient(killer) 
	    && IsClientInGame(victim) && !IsFakeClient(victim))
	{
		Handle hKiller = json_object(); 
		Handle hVictim = json_object(); 
		char sBuffer[1024];
		
		//PlatformID
		Format(sBuffer, sizeof(sBuffer), "%s", iCommunityID[killer]);
		json_object_set_new(hKiller, "platformID", json_string(sBuffer));
		Format(sBuffer, sizeof(sBuffer), "%s", iCommunityID[victim]);
		json_object_set_new(hVictim, "platformID", json_string(sBuffer));
		
		//Kills
		Format(sBuffer, sizeof(sBuffer), "%i", 1);
		json_object_set_new(hKiller, "kills", json_string(sBuffer));
		Format(sBuffer, sizeof(sBuffer), "%i", 0);
		json_object_set_new(hVictim, "kills", json_string(sBuffer));
			
		//Deaths
		Format(sBuffer, sizeof(sBuffer), "%i", 0);
		json_object_set_new(hKiller, "deaths", json_string(sBuffer));
		Format(sBuffer, sizeof(sBuffer), "%i", 1);
		json_object_set_new(hVictim, "deaths", json_string(sBuffer));
			
		//Name
		GetClientName(killer, sBuffer, sizeof(sBuffer));
		json_object_set_new(hKiller, "name", json_string(sBuffer));
		GetClientName(victim, sBuffer, sizeof(sBuffer));
		json_object_set_new(hVictim, "name", json_string(sBuffer));
			
		//Rank
		Format(sBuffer, sizeof(sBuffer), "%i", iClientRank[killer]);
		json_object_set_new(hKiller, "rank", json_string(sBuffer));
		Format(sBuffer, sizeof(sBuffer), "%i", iClientRank[victim]);
		json_object_set_new(hVictim, "rank", json_string(sBuffer));
			
		//Weapon
		new String:sWeaponName[64];
		GetClientWeapon(killer, sWeaponName, sizeof(sWeaponName));
		json_object_set_new(hKiller, "weapon", json_string(sWeaponName));
		GetClientWeapon(victim, sWeaponName, sizeof(sWeaponName));
		json_object_set_new(hVictim, "weapon", json_string(sWeaponName));

		json_array_append(hPlayerArray, hKiller);
		json_array_append(hPlayerArray, hVictim);
	}
	
	char sJSONList[2048];
	json_dump(hPlayerArray, sJSONList, sizeof(sJSONList));

	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "player_dict_list", sJSONList);

	char json_escaped[2048];
	int output_len = url_escape(json_escaped, sizeof(json_escaped), sJSONList);
	Leet_Log("Submitted Kill: %s\n", json_escaped);

	char params[2048];
	Format(params, sizeof(params), "nonce=%s&map_title=%s&player_dict_list=", sTime, sMapname); 
	int len = output_len + strlen(params);

	append_string(params, strlen(params), json_escaped, output_len);

	char sHash[2048];
	digest_string_with_key_length(cv_sServerSecret, params, sHash, 2048, len);	

	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-type", "application/x-www-form-urlencoded");
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Key", cv_sAPIKey);
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Sign", sHash);
	
	SteamWorks_SetHTTPCallbacks(hRequest, OnSubmittingMatchResults);
	SteamWorks_SendHTTPRequest(hRequest);
	
	return Plugin_Continue;
}

public int OnSubmittingMatchResults(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
	if (bFailure || !bRequestSuccessful)
	{
		Leet_Log("Error submitting match results. Error code: %i", view_as<int>(eStatusCode));
		#if defined DEBUG
		Leet_DebugLog("Error submitting match results:\n-bFailure = %s\n-bRequestSuccessful = %s\n-eStatusCode = %i", bFailure ? "True" : "False", bRequestSuccessful ? "True" : "False", view_as<int>(eStatusCode));
		#endif
		return;
	}
	
	int size = 0;
	SteamWorks_GetHTTPResponseBodySize(hRequest, size);
	
	char[] sBuffer = new char[size];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBuffer, size);
	
	Handle hJSON = json_load(sBuffer);
	
	for (int i = 0; i < json_array_size(hJSON); i++)
	{
		Handle hSteamID = json_array_get(hJSON, i);
		
		char sBuffer2[1024];
		json_string_value(hSteamID, sBuffer2, sizeof(sBuffer2));
		
		int retrieve = CheckAgainstCommunityID(sBuffer2);
		
		if (retrieve > 0)
			KickClient(retrieve, "Please go to Leet.gg and register for the server.");
	}
}

int CheckAgainstCommunityID(const char[] sCommunityID)
{
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			if (strcmp(iCommunityID[i], sCommunityID))
				return i;
	return 0;
}

void IssuePlayerAward(int client, int amount, const char[] sReason)
{
	if (!cv_bStatus || !bServerSetup)
		return;
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", API_URL, API_URL_PUT_MATCH_RESULTS);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	Handle hArray = json_array(); char sBuffer[1024];
	
	Format(sBuffer, sizeof(sBuffer), "%i", g_player_platformid[client]);
	json_array_append_new(hArray, json_string(sBuffer));
	
	GetClientName(client, sBuffer, sizeof(sBuffer));
	json_array_append_new(hArray, json_string(sBuffer));
	
	Format(sBuffer, sizeof(sBuffer), "%i", amount);
	json_array_append_new(hArray, json_string(sBuffer));
	
	Format(sBuffer, sizeof(sBuffer), "%s", sReason);
	json_array_append_new(hArray, json_string(sBuffer));
	
	char sAward[2048];
	json_dump(hArray, sAward, sizeof(sAward));

	char params[2048];
	Format(params, sizeof(params), "award=%s", sAward); 
	
	char sHash[2048];
	digest_string_with_key(cv_sServerSecret, params, sHash, 2048);	
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "award", sAward);
	
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Content-type", "application/x-www-form-urlencoded");
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Key", cv_sAPIKey);
	SteamWorks_SetHTTPRequestHeaderValue(hRequest, "Sign", sHash);
	
	Handle hPack = CreateDataPack();
	WritePackCell(hPack, GetClientUserId(client));
	WritePackCell(hPack, amount);
	WritePackString(hPack, sReason);
	
	SteamWorks_SetHTTPRequestContextValue(hRequest, GetClientUserId(client));
	
	SteamWorks_SetHTTPCallbacks(hRequest, OnIssueAward);
	SteamWorks_SendHTTPRequest(hRequest);
}



public int OnIssueAward(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1)
{
	ResetPack(data1);
	
	int client = GetClientOfUserId(ReadPackCell(data1));
	int amount = ReadPackCell(data1);
	
	char sReason[1024];
	ReadPackString(data1, sReason, sizeof(sReason));
	
	CloseHandle(data1);
	
	if (client < 1)
	{
		Leet_Log("Error issuing a reward to a client, client index is invalid.");
		return;
	}
	
	if (bFailure || !bRequestSuccessful)
	{
		Leet_Log("Error issuing a reward to the client '%L'. Error code: %i", client, view_as<int>(eStatusCode));
		#if defined DEBUG
		Leet_DebugLog("Pulling client rewards issued failure for %L:\n-bFailure = %s\n-bRequestSuccessful = %s\n-eStatusCode = %i", client, bFailure ? "True" : "False", bRequestSuccessful ? "True" : "False", view_as<int>(eStatusCode));
		#endif
		return;
	}
	
	int size = 0;
	SteamWorks_GetHTTPResponseBodySize(hRequest, size);
	
	char[] sBuffer = new char[size];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBuffer, size);
	
	Handle hJSON = json_load(sBuffer);
	
	if (json_object_get_bool(hJSON, "award_authorized"))
	{
		g_player_btchold[client] += amount;
		PrintToChatAll("%N earned: %i Satoshi for: %s", client, amount, sReason);
	}
}

public void OnEntityCreated(int entity, const char[] sClassname)
{
	Leet_Log("entity %s\n", sClassname);
	if (StrEqual(sClassname, "chicken")) {
		SetEntPropFloat(entity, Prop_Data, "m_explodeDamage", float(4000));
		SetEntPropFloat(entity, Prop_Data, "m_explodeRadius", float(4000));
		HookSingleEntityOutput(entity, "OnBreak", OnChickenKill);
	}
}


public void OnChickenKill(const char[] output, int caller, int activator, float delay)
{
	Leet_Log("On Chicken Kill.");
	char name[64];
	if(!GetClientName(activator, name, sizeof(name)))
		PrintToChatAll("%s, otherise known as %s killed a chicken. Not vegan confirmed.", name, g_player_name[activator]);
	//SetEntPropFloat(caller, Prop_Data, "m_explodeDamage", float(20));
	//SetEntPropFloat(caller, Prop_Data, "m_explodeRadius", float(10000));
	//IssuePlayerAward(activator, 100, "Chicken Kill");
}

public Action OnSpawnChicken(int client, int args)
{
	if (!cv_bStatus || !bServerSetup)
		return Plugin_Handled;
	
	float fPos[3];
	if (!CalculateLookPosition(client, fPos))
	{
		PrintToChat(client, "Error spawning a chicken, invalid look position.");
		return Plugin_Handled;
	}
	
	int entity = CreateEntityByName("chicken");
	
	if (IsValidEntity(entity))
	{
		DispatchSpawn(entity);
		TeleportEntity(entity, fPos, NULL_VECTOR, NULL_VECTOR);
		
		CreateChickenParticle(entity);
		PrintToChat(client, "You have spawned a chicken, congratulations...");
	}
	
	return Plugin_Handled;
}

bool CalculateLookPosition(int client, float fPos[3], int entity = -1)
{
	float fEyePosition[3];
	GetClientEyePosition(client, fEyePosition);
	
	float fEyeAngles[3];
	GetClientEyeAngles(client, fEyeAngles);
	
	Handle hTrace = TR_TraceRayFilterEx(fEyePosition, fEyeAngles, MASK_SOLID, RayType_Infinite, OnHitPlayers);
	TR_GetEndPosition(fPos, hTrace);
	
	int collision = TR_GetEntityIndex(hTrace);
	bool bHit = TR_DidHit(hTrace);
	
	if (entity != -1 && entity == collision)
	{
		return false;
	}
	
	CloseHandle(hTrace);
	
	return bHit;
}

public bool OnHitPlayers(int entity, int contentsmask, any data)
{
	return !((entity > 0) && (entity <= MaxClients));
}

void CreateChickenParticle(int chicken)
{
	int entity = CreateEntityByName("info_particle_system");
	
	if (IsValidEntity(entity))
	{
		float fPos[3];
		GetEntPropVector(chicken, Prop_Send, "m_vecOrigin", fPos);
		TeleportEntity(entity, fPos, NULL_VECTOR, NULL_VECTOR);
		
		DispatchKeyValue(entity, "effect_name", "chicken_gone_feathers");
		
		DispatchKeyValue(entity, "angles", "-90 0 0");
		DispatchSpawn(entity);
		ActivateEntity(entity);
		
		AcceptEntityInput(entity, "Start");
		
		CreateTimer(5.0, KillEntity, EntIndexToEntRef(entity));
	}
}

public Action KillEntity(Handle timer, any data)
{
	int entity = EntRefToEntIndex(data);
	
	if (IsValidEntity(entity))
		AcceptEntityInput(entity, "Kill");
}

void Leet_Log(const char[] format, any...)
{
	char buffer[256]; char path[PLATFORM_MAX_PATH];
	VFormat(buffer, sizeof(buffer), format, 2);
	BuildPath(Path_SM, path, sizeof(path), "logs/Leet_Logs.log");
	LogToFileEx(path, "%s", buffer);
}

#if defined DEBUG
void Leet_DebugLog(const char[] format, any...)
{
	char buffer[256]; char path[PLATFORM_MAX_PATH];
	VFormat(buffer, sizeof(buffer), format, 2);
	BuildPath(Path_SM, path, sizeof(path), "logs/Leet_Debug.log");
	LogToFileEx(path, "%s", buffer);
}
#endif

void CalculateEloRank(int winner, int loser, bool penalize_loser = true)
{
	int winner_rank = iClientRank[winner];
	int rank_diff = iClientRank[winner] - iClientRank[loser];
	
	float exp = (rank_diff * -1) / 400.0;
	
	float odds = 1.0 / (1.0 + Pow(10.0, exp));
	
	int k;
	if (iClientRank[winner] < 2100)
		k = 32;
	else if (iClientRank[winner] >= 2100 && iClientRank[winner] < 2400)
		k = 24;
	else
		k = 16;
	
	iClientRank[winner] = RoundFloat(iClientRank[winner] + (k * (1 - odds)));
	
	if (penalize_loser)
	{
		int new_rank_diff = iClientRank[winner] - winner_rank;
		iClientRank[loser] -= new_rank_diff;
	}
	
	if (iClientRank[loser] < 1)
		iClientRank[loser] = 1;
} 
