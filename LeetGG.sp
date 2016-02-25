/*
Leet CSGO Server Plugin

Base URLs:
api-dot-1337coin.appspot.com - Known working API
apitest-dot-1337coin.appspot.com - Bleeding edge API

General Flow:

Server is started
Server settings is asked for from the Leet API
/api/get_server_info
Code example available on API docs
Returns JSON with information on minimum hold for a player, promo server, allowing non authorized players, server rake, leet rake and balance increments

Player Enters 
User's ID is converted into Steam64 and kept in an array of players, this is referred to in the docs at the platformID
Request made to Leet API to attempt to activate the player
/api/activate_player
If non authorized players are allowed (from the server settings) then it doesn’t matter if it returns back as true for player_authorized, if not though then the player should be kicked for not being authorized
Settings for the player are included in the response as well

On Player Death
If both players is authorized 
Add incrementBTC - leetCoinRake and serverRake percentages to killer
Decrease by incrementBTC for loser
If both players authorized and isPromo
Add incrementBTC - leetCoinRake and serverRake percentages to killer
Don’t decrease for loser
If one or both of the players is not authorized
Do nothing
Add this information to the number of kills and deaths for each player to be submitted to the server
If the players server balance is below the minimum balance for the server kick the player

Submitting match results
Should have a counter to do it every 30 seconds
Submit based on array of players and kills and deaths, all real math is done server side 
/api/put_match_results
Returns back a list of steam64 ID to kick for balance being too low/etc

Issuing awards
Based on certain events (such as killing a chicken is our example) players can be given awards from the server rake amounts
/api/issue_award
It returns whether the award_authorized and if it's true add to the the balance of the player 

Deactivate Player
If a player is kicked or they choose to exit the leet api should be told the player is leaving the server
/api/deactivate_player

Chicken death
One feature we have on our promo server is we give an award if the player kills a chicken in game 
This would use the Issue Award function you would build earlier and give 100 satoshi 

*/

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <smjansson>
#include <cURL>

//Uncomment to enable debug mode.
//#define DEBUG

#define PLUGIN_NAME		"Leet GG"
#define PLUGIN_AUTHOR	"Leetcoin Team"
#define PLUGIN_DES		"The official Leet.gg plugin for Sourcemod. This plugin takes advantage of our native API."
#define PLUGIN_VERSION	"1.0.0"
#define PLUGIN_URL		"http://www.leet.gg/"

#define API_URL			"api-dot-1337coin.appspot.com"
#define API_URL_BLEED	"apitest-dot-1337coin.appspot.com"
#define TEST_URL		"https://www.leet.gg/server/view/agpzfjEzMzdjb2luchMLEgZTZXJ2ZXIYgICA9MD-_gsM"

#define API_URL_GET_SERVER_INFO		"/api/get_server_info"
#define API_URL_ACTIVATE_PLAYER		"/api/activate_player"
#define API_URL_PUT_MATCH_RESULTS	"/api/put_match_results"
#define API_URL_ISSUE_AWARD			"/api/issue_award"
#define API_URL_DEACTIVATE_PLAYER	"/api/deactivate_player"

Handle hConVars[2];
bool cv_bStatus; char cv_sAPIKey[256] = "gUNXh9MVyn5RpDXbP4kTEl91IxdJRM";

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
int iCommunityID[MAXPLAYERS + 1];
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
	hConVars[1] = CreateConVar("sm_leetgg_api", "", "API key to use.", FCVAR_PROTECTED);
	
	HookEvent("player_death", OnPlayerDeath);
	
	RegAdminCmd("sm_chicken", OnSpawnChicken, ADMFLAG_ROOT, "Spawn a chicken where you\'re looking.");
	
	CreateTimer(30.0, SubmitPlayerInformation, _, TIMER_REPEAT);
	
	AutoExecConfig();
}

public void OnConfigsExecuted()
{
	cv_bStatus = GetConVarBool(hConVars[0]);
	GetConVarString(hConVars[1], cv_sAPIKey, sizeof(cv_sAPIKey));
	
	if (!cv_bStatus)
	{
		bServerSetup = false;
		return;
	}
	
	if (strlen(cv_sAPIKey) == 0)
	{
		Leet_Log("Error retrieving server information, API key is missing.");
		bServerSetup = false;
		return;
	}
	
	Leet_Log("Requesting server information...");
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", TEST_URL, API_URL_GET_SERVER_INFO);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	char sHash[2048];
	curl_hash_string(sTime, sizeof(sTime), Openssl_Hash_SHA512, sHash, sizeof(sHash));
	
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
		#endif
		return;
	}
	
	/*
		{
			"minimumBTCHold": 0,
			"no_death_penalty": true,
			"allow_non_authorized_players": false,
			"admissionFee": null,
			"serverRakeBTCPercentage": 0.0,
			"api_version": "01B",
			"incrementBTC": 1000,
			"leetcoinRakePercentage": 0.0,
			"authorization": true
		}
	*/
	
	int size = 0;
	SteamWorks_GetHTTPResponseBodySize(hRequest, size);
	
	char[] sBuffer = new char[size];
	SteamWorks_GetHTTPResponseBodyData(hRequest, sBuffer, size);
	
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
	
	float total_rake = g_serverRakeBTCPercentage + g_leetcoinRakePercentage;
	kill_reward = RoundToCeil(g_incrementBTC - (g_incrementBTC * total_rake));
	
	Leet_Log("Server information retrieval successful.");
	bServerSetup = true;
}

public void OnClientAuthorized(int client, const char[] sAuth)
{
	if (!cv_bStatus || !bServerSetup)
	{
		return;
	}
	
	iCommunityID[client] = 0;
	iClientRank[client] = 0;
	iStatsKills[client] = 0;
	iStatsDeaths[client] = 0;
	
	char sCommunityID[128];
	GetClientAuthId(client, AuthId_SteamID64, sCommunityID, sizeof(sCommunityID));
	
	iCommunityID[client] = StringToInt(sCommunityID);
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", TEST_URL, API_URL_ACTIVATE_PLAYER);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	char sHash[2048];
	curl_hash_string(sTime, sizeof(sTime), Openssl_Hash_SHA512, sHash, sizeof(sHash));
	
	char sAuthID[128];
	GetClientAuthId(client, AuthId_SteamID64, sAuthID, sizeof(sAuthID));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "platformid", sAuthID);
	
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
	/*
		{
			"player_btchold": 0,
			"player_name": "leet-test",
			"player_platformid": "765611912315782326",
			"player_key": "agpzfjEzMzdjb2luchMLEgZQbGASDFQFASIYgICAoL6ouwgM",
			"player_previously_active": false,
			"player_rank": 1600,
			"player_authorized": true,
			"default_currency_conversion": "2.629e-06",
			"default_currency_display": "USD",
			"authorization": true
		}
		
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
	*/
	
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
	json_object_get_string(hJSON, "g_default_currency_conversion", g_default_currency_conversion[client], 64);
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
	if (!cv_bStatus || !bServerSetup)
	{
		return;
	}
	
	iCommunityID[client] = 0;
	iClientRank[client] = 0;
	iStatsKills[client] = 0;
	iStatsDeaths[client] = 0;
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", TEST_URL, API_URL_DEACTIVATE_PLAYER);
	
	Handle hRequest = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, sURL);
	
	float fTime = float(GetTime());
	
	char sTime[128];
	FloatToString(fTime, sTime, sizeof(sTime));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "nonce", sTime);
	
	char sHash[2048];
	curl_hash_string(sTime, sizeof(sTime), Openssl_Hash_SHA512, sHash, sizeof(sHash));
	
	char sAuthID[128];
	GetClientAuthId(client, AuthId_SteamID64, sAuthID, sizeof(sAuthID));
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "platformid", sAuthID);
	
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
	
	/*
		{
			"player_previously_active": false,
			"player_authorized": false,
			"player_key": "agpzfjEzMzdjb2luchMLEgZQbGF5ZXIYgICAoL6ouwgM",
			"authorization": true
		}
		
		bool g_player_previously_active;
		bool g_player_authorized;
		char g_player_key[256];
		bool g_authorization;
	*/
	
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
	{
		return;
	}
	
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	if (client != attacker)
	{
		if (g_player_authorized[client] && g_player_authorized[attacker])
		{
			g_player_btchold[attacker] += kill_reward;
			
			if (!g_no_death_penalty)
			{
				g_player_btchold[client] -= kill_reward;
			}
			
			int new_winner_rank; int new_loser_rank;
			CalculateEloRank(attacker, client, new_winner_rank, new_loser_rank, false);
			
			iClientRank[client] = new_loser_rank;
			iClientRank[attacker] = new_winner_rank;
			
			if (g_player_btchold[client] < g_minimumBTCHold)
			{
				KickClient(client, "Your balance is too low to continue playing.  Go to leet.gg to add more btc to your server hold.");
			}
			
			PrintToChatAll("%N earned: %i Satoshi for killing %N", attacker, kill_reward, client);
		}
		
		iStatsKills[attacker]++;
		iStatsDeaths[client]++;
	}
}

public Action SubmitPlayerInformation(Handle timer, any data)
{
	if (!cv_bStatus || !bServerSetup)
	{
		return Plugin_Continue;
	}
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", TEST_URL, API_URL_PUT_MATCH_RESULTS);
	
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
			Handle hSingle = json_array(); char sBuffer[1024];
			
			//PlatformID
			Format(sBuffer, sizeof(sBuffer), "%i", g_player_platformid[i]);
			json_array_append_new(hSingle, json_string(sBuffer));
			
			//Kills
			Format(sBuffer, sizeof(sBuffer), "%i", iStatsKills[i]);
			json_array_append_new(hSingle, json_string(sBuffer));
			
			//Deaths
			Format(sBuffer, sizeof(sBuffer), "%i", iStatsDeaths[i]);
			json_array_append_new(hSingle, json_string(sBuffer));
			
			//Name
			GetClientName(i, sBuffer, sizeof(sBuffer));
			json_array_append_new(hSingle, json_string(sBuffer));
			
			//Rank
			Format(sBuffer, sizeof(sBuffer), "%i", iClientRank[i]);
			json_array_append_new(hSingle, json_string(sBuffer));
			
			//Weapon
			Format(sBuffer, sizeof(sBuffer), "N/A");
			json_array_append_new(hSingle, json_string(sBuffer));
		}
	}
	
	char sJSONList[2048];
	json_dump(hPlayerArray, sJSONList, sizeof(sJSONList));
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "player_dict_list", sMapname);

	char sHash[2048];
	curl_hash_string(sTime, sizeof(sTime), Openssl_Hash_SHA512, sHash, sizeof(sHash));
	
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
		{
			KickClient(retrieve, "Please go to Leet.gg and register for the server.");
		}
	}
}

int CheckAgainstCommunityID(const char[] sCommunityID)
{
	for (int i = 1; i <= MaxClients; i++)
	{
		if (IsClientInGame(i) && !IsFakeClient(i))
		{
			if (iCommunityID[i] == StringToInt(sCommunityID))
			{
				return i;
			}
		}
	}
	
	return 0;
}

void IssuePlayerAward(int client, int amount, const char[] sReason)
{
	if (!cv_bStatus || !bServerSetup)
	{
		return;
	}
	
	char sURL[512];
	Format(sURL, sizeof(sURL), "%s%s", TEST_URL, API_URL_PUT_MATCH_RESULTS);
	
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
	
	SteamWorks_SetHTTPRequestGetOrPostParameter(hRequest, "award", sAward);

	char sHash[2048];
	curl_hash_string(sTime, sizeof(sTime), Openssl_Hash_SHA512, sHash, sizeof(sHash));
	
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
	if (StrEqual(sClassname, "chicken"))
	{
		HookSingleEntityOutput(entity, "OnBreak", OnChickenKill);
	}
}

public void OnChickenKill(const char[] output, int caller, int activator, float delay)
{
	IssuePlayerAward(activator, 100, "Chicken Kill");
}

public Action OnSpawnChicken(int client, int args)
{
	if (!cv_bStatus || !bServerSetup)
	{
		return Plugin_Handled;
	}
	
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
	{
		AcceptEntityInput(entity, "Kill");
	}
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

//1600
void CalculateEloRank(int client, int loser, int new_winner_rank, int new_loser_rank, bool penalize_loser = true)
{
	int winner_rank = iClientRank[client];
	int loser_rank = iClientRank[loser];
	
	int rank_diff = winner_rank - loser_rank;
	
	float exp = (rank_diff * -1) / 400.0;
	
	float odds = 1.0 / (1.0 + Pow(10.0, exp));
	
	int k;
	if (winner_rank < 2100)
	{
		k = 32;
	}
	else if (winner_rank >= 2100 && winner_rank < 2400)
	{
		k = 24;
	}
	else
	{
		k = 16;
	}
	
	new_winner_rank = RoundFloat(winner_rank + (k * (1 - odds)));
	
	if (penalize_loser)
	{
		int new_rank_diff = new_winner_rank - winner_rank;
		new_loser_rank = loser_rank - new_rank_diff;
	}
	else
	{
		new_loser_rank = loser_rank;
	}
	
	if (new_loser_rank < 1)
	{
		new_loser_rank = 1;
	}
} 
