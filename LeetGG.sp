#pragma semicolon 1

#include <string>
#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <Leet>

//Uncomment to enable debug mode.
#define DEBUG

#define PLUGIN_NAME		"Leet GG"
#define PLUGIN_AUTHOR	"Leetcoin Team"
#define PLUGIN_DES		"The official Leet.gg plugin for Sourcemod. This plugin takes advantage of our native API."
#define PLUGIN_VERSION	"1.0.0"
#define PLUGIN_URL		"https://www.leet.gg/"

Handle hConVars[3];
bool cv_bStatus; 
char cv_sAPIKey[256];
char cv_sServerSecret[256];

bool bServerSetup;

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
	hConVars[2] = CreateConVar("sm_leetgg_server_secret", "", "Server Secret to use", FCVAR_PROTECTED);
	
	HookEvent("player_death", OnPlayerDeath, EventHookMode_Post);
	HookEvent("round_end", OnRoundEnd);
	
	//CreateTimer(30.0, SubmitPlayerInformation, _, TIMER_REPEAT);

	//HookEntityOutput("chicken", "OnBreak", OnChickenKill);
	
	AutoExecConfig();
}

public Action OnRoundEnd(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			// PrintToChat(i, "Your current balance is: %i satoshi.", g_player_btchold[i]);
			PrintToChat(i, "Your current balance is: geese satoshi.");
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
		bServerSetup = false;
		return;
	}
	
	bServerSetup = Leet_OnPluginLoad(cv_sAPIKey, cv_sServerSecret);	

	//SteamWorks_SetHTTPCallbacks(hRequest, OnPullingServerInfo);
	//SteamWorks_SendHTTPRequest(hRequest);
}

public int OnPullingServerInfo(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
	if (bFailure || !bRequestSuccessful)
	{
		bServerSetup = false;
		Leet_Log("Error retrieving server information. Error code: %i", view_as<int>(eStatusCode));
		return;
	}
	
	
	Leet_Log("Server information retrieval successful.");
	bServerSetup = true;
}

public void OnClientAuthorized(int client, const char[] sAuth)
{
	// Exit if the server isn't set up or the plugin is turned off
	if (!cv_bStatus || !bServerSetup)
		return;
	
	char sAuthID[128];
	GetClientAuthId(client, AuthId_SteamID64, sAuthID, sizeof(sAuthID));
	
	Leet_OnClientConnected(sAuthID);
	
	//SteamWorks_SetHTTPCallbacks(hRequest, OnPullingClientInfo);
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
		return;
	}
	
	/*if (g_authorization && !g_player_authorized[client])
	{
		KickClient(client, "You are not authorized to join this server.");
	} */
	
	Leet_Log("Client '%N' information retrieval successful.", client);
}

public void OnClientDisconnect(int client)
{

	Leet_Log("On client disconnect.");

	if (!cv_bStatus || !bServerSetup)
	{
		return;
	}
	
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
		return;
	}
	
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
		/*if (g_player_authorized[client] && g_player_authorized[attacker])
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
		iStatsDeaths[client]++; */
	}
	
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (strcmp(sArgs, "balance", false) == 0 || strcmp(sArgs, "!balance", false) == 0)
	{
		//PrintToChat(client, "Your current balance is: %i satoshi.", g_player_btchold[client]);
		PrintToChat(client, "Your current balance is: goose satoshi.");
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
	
	char sMapname[64];
	GetCurrentMap(sMapname, sizeof(sMapname));
	
	return Plugin_Continue;
}

public int OnSubmittingMatchResults(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode)
{
	if (bFailure || !bRequestSuccessful)
	{
		Leet_Log("Error submitting match results. Error code: %i", view_as<int>(eStatusCode));
		return;
	}
	
	/*Handle hJSON = json_load(sBuffer);
	
	for (int i = 0; i < json_array_size(hJSON); i++)
	{
		Handle hSteamID = json_array_get(hJSON, i);
		
		char sBuffer2[1024];
		json_string_value(hSteamID, sBuffer2, sizeof(sBuffer2));
		
		int retrieve = CheckAgainstCommunityID(sBuffer2);
		
		if (retrieve > 0)
			KickClient(retrieve, "Please go to Leet.gg and register for the server.");
	}*/
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
	
}



public int OnIssueAward(Handle hRequest, bool bFailure, bool bRequestSuccessful, EHTTPStatusCode eStatusCode, any data1)
{
	if (bFailure || !bRequestSuccessful)
	{
		//Leet_Log("Error issuing a reward to the client '%L'. Error code: %i", client, view_as<int>(eStatusCode));
		//Leet_Log("Error issuing a reward to the client Error code: %i", view_as<int>(eStatusCode));
		#if defined DEBUG
		//Leet_DebugLog("Pulling client rewards issued failure for %L:\n-bFailure = %s\n-bRequestSuccessful = %s\n-eStatusCode = %i", client, bFailure ? "True" : "False", bRequestSuccessful ? "True" : "False", view_as<int>(eStatusCode));
		#endif
		return;
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
	if(IsClientInGame(activator) && !IsFakeClient(activator)) {
		GetClientName(activator, name, sizeof(name));
		PrintToChatAll("%s, otherise known as %s killed a chicken. Not vegan confirmed.", name);

		new maxClients = GetMaxClients();
		new Float:vec[3];
		GetEntPropVector(caller, Prop_Send, "m_vecOrigin", vec);

		for (new i = 1; i < maxClients; ++i) {
			if (!IsClientInGame(i) || !IsPlayerAlive(i))
				continue;
	
			Leet_Log("OnChickenKill Loop");
			new Float:radius = 1000;	
			new Float:pos[3];
			GetClientEyePosition(i, pos);
			new Float:distance = GetVectorDistance(vec, pos);
			if (distance > radius)
				continue;

			new damage = 500;
			damage = RoundToFloor(damage * (radius - distance) / radius);
			SlapPlayer(i, damage, false);
		}
		SetEntPropFloat(caller, Prop_Data, "m_explodeDamage", float(0));
		SetEntPropFloat(caller, Prop_Data, "m_explodeRadius", float(10));
		IssuePlayerAward(activator, 100, "Chicken Kill");
	}
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
