#pragma semicolon 1

#include <string>
#include <sourcemod>
#include <sdktools>
#include <SteamWorks>
#include <Leet>

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
	HookEvent("player_connect_client", OnPlayerConnect, EventHookMode_Post);
	
	CreateTimer(30.0, OnRoundEnd, _, TIMER_REPEAT);
	//HookEntityOutput("chicken", "OnBreak", OnChickenKill);
	AutoExecConfig();
}

public Action OnPlayerConnect(Event event, const char[] name, bool dontBroadcast) {
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	Leet_OnClientConnected(client);
}

public Action OnRoundEnd(Event event, const char[] name, bool dontBroadcast) {
	for (int i = 1; i <= MaxClients; i++)
		if (IsClientInGame(i) && !IsFakeClient(i))
			Leet_GetBalance(i);

	Leet_OnRoundEnd();
	return Plugin_Continue;
}

public void OnConfigsExecuted()
{
	cv_bStatus = GetConVarBool(hConVars[0]);
	GetConVarString(hConVars[1], cv_sAPIKey, 256);
	GetConVarString(hConVars[2], cv_sServerSecret, 256);
	
	if (!cv_bStatus) {
		bServerSetup = false;
		return;
	}
	
	if (strlen(cv_sAPIKey) == 0 || strlen(cv_sServerSecret) == 0) {
		Leet_Log("Error retrieving server information, API key or Server secret is missing.");
		bServerSetup = false;
		return;
	}
	
	bServerSetup = Leet_OnPluginLoad(cv_sAPIKey, cv_sServerSecret);	
}

/*public void OnClientAuthorized(int client, const char[] sAuth)
{
	if (!cv_bStatus || !bServerSetup)
		return;	

	Leet_OnClientConnected(client);
} */


public void OnClientDisconnect(int client)
{
	if (!cv_bStatus || !bServerSetup)
		return;

	Leet_OnClientDisconnected(client);
}


public void OnPlayerDeath(Handle event, const char[] name, bool dontBroadcast)
{
	if (!cv_bStatus || !bServerSetup)
		return;
	
	int victim = GetClientOfUserId(GetEventInt(event, "userid"));
	int attacker = GetClientOfUserId(GetEventInt(event, "attacker"));
	
	Leet_OnPlayerKill(attacker, victim);
}

public Action OnClientSayCommand(int client, const char[] command, const char[] sArgs)
{
	if (strcmp(sArgs, "balance", false) == 0 || strcmp(sArgs, "!balance", false) == 0)
	{
		Leet_GetBalance(client);
 		return Plugin_Handled;
	}
	return Plugin_Continue;
}

void IssuePlayerAward(int client, int amount, const char[] sReason)
{
	if (!cv_bStatus || !bServerSetup)
		return;
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
