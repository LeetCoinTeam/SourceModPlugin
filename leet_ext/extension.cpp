#include "extension.h"
#include "ThreadPool.h"

/**
 * @file extension.cpp
 */
ThreadPool pool(4);
LeetApi *leetApi;
Leet g_Leet;		/**< Global singleton for extension's main interface */

SMEXT_LINK(&g_Leet);

bool GetServerInformation(const std::string key, const std::string secret) {
	leetApi->setApiKey(key);
	leetApi->setApiSecret(secret);
	return leetApi->getServerInformation();
}

void GetClientInformation(const std::string steam64, IGamePlayer *pPlayer) {
	bool allowed = leetApi->activatePlayer(steam64);
	if(!allowed && pPlayer->IsConnected() && !pPlayer->IsFakeClient()) {
		pPlayer->Kick("Please go to Leet.gg and register for this server. You are currently not authorized.");
	}
	return;
}

void DeactivateClient(const std::string steam64, IGamePlayer *pPlayer) {
	bool allowed = leetApi->deactivatePlayer(steam64);
	if(!allowed && pPlayer->IsConnected() && !pPlayer->IsFakeClient()) {
		pPlayer->Kick("Please go to Leet.gg and register for this server. You are currently not authorized.");
	}
	return;
}

void ReportKill(const std::string killer64, const std::string victim64, IGamePlayer *pVictim) {
	bool kick_victim = leetApi->onPlayerKill(killer64, victim64);
	if(kick_victim && pVictim->IsConnected() && !pVictim->IsFakeClient()) {
		pVictim->Kick("Your balance is too low. Go to Leet.gg and re-up.");
	}
	return;
}

void submitMatchResults() {
	std::list<std::string> kick_players = leetApi->submitMatchResults();
}

cell_t Leet_OnPluginLoad(IPluginContext *pContext, const cell_t *params) {
	char *api_key, *api_secret;
	pContext->LocalToString(params[1], &api_key);
	pContext->LocalToString(params[2], &api_secret);
	std::string key(api_key);
	std::string secret(api_secret);
	std::cout << "Created Thread." << std::endl;
	auto result = pool.enqueue(GetServerInformation, key, secret);
	// TODO: fix this return result.
	return 1;
}


cell_t Leet_OnClientConnected(IPluginContext *pContext, const cell_t *params) {
	int player = (unsigned int)params[1];

	IGamePlayer *pPlayer = playerhelpers->GetGamePlayer(player);

	std::ostringstream steam64_stream;
	steam64_stream << pPlayer->GetSteamId64();

	std::string steam64(steam64_stream.str());
	if(steam64.length() <= 1) {
		std::cout << "Tryed to register bot or entity on Leet." << std::endl;
		if(!leetApi->getAllowUnauthorized()) {
			pPlayer->Kick("Goodbye Bot :)");
		}
	}
	pool.enqueue(GetClientInformation, steam64, pPlayer);
	return 0;
}


cell_t Leet_OnClientDisconnected(IPluginContext *pContext, const cell_t *params) {
	// TODO: Not Fake, Is connected...
	unsigned int player = (unsigned int)params[1];

	IGamePlayer *pPlayer = playerhelpers->GetGamePlayer(player);

	std::ostringstream steam64_stream;
	steam64_stream << pPlayer->GetSteamId64();

	std::string steam64(steam64_stream.str());
	if(steam64.length() <= 1) {
		std::cout << "Tryed to register bot or entity on Leet." << std::endl;
		return leetApi->getAllowUnauthorized();
	}

	pool.enqueue(DeactivateClient, steam64, pPlayer);
	return 0;
}

cell_t Leet_OnPlayerKill(IPluginContext *pContext, const cell_t *params) {
	unsigned int killer, victim;
	killer = (unsigned int)params[1];
	victim = (unsigned int)params[2];

	if(killer == victim) {
		std::cout << "Not recording suicide." << std::endl;
		return 0;
	}

	IGamePlayer *pKiller = playerhelpers->GetGamePlayer(killer);
	IGamePlayer *pVictim = playerhelpers->GetGamePlayer(victim);

	if(!pKiller || !pKiller->IsConnected() || pKiller->IsFakeClient()
		|| !pVictim || !pVictim->IsConnected() || pVictim->IsFakeClient()) {
		std::cout << "Killer or victim was fake or not connected." << std::endl;
		return 0;
	}

	std::ostringstream killer_stream, victim_stream;
	killer_stream << pKiller->GetSteamId64();
	victim_stream << pVictim->GetSteamId64();

	pool.enqueue(ReportKill, killer_stream.str(), victim_stream.str(), pVictim);

	return 0;
}

cell_t Leet_OnRoundEnd(IPluginContext *pContext, const cell_t *params) {
	pool.enqueue(submitMatchResults);
	return 0;
}

cell_t Leet_GetBalance(IPluginContext *pContext, const cell_t *params) {
	unsigned int player;
	player = (unsigned int)params[1];

	IGamePlayer *pPlayer = playerhelpers->GetGamePlayer(player);

	std::ostringstream player_stream;
	player_stream << pPlayer->GetSteamId64();

	uint64_t balance = leetApi->getBalance(player_stream.str());

	player_stream.str("");
	player_stream.clear();

	player_stream << "Your balance is " << balance << " satoshi." << std::endl;

	gamehelpers->TextMsg(player, TEXTMSG_DEST_NOTIFY, player_stream.str().c_str());
	
	return 0;
}

const sp_nativeinfo_t LeetNatives[] = 
{
	{"Leet_OnPluginLoad", Leet_OnPluginLoad},
	{"Leet_OnClientConnected", Leet_OnClientConnected},
	{"Leet_OnClientDisconnected", Leet_OnClientDisconnected},
	{"Leet_OnPlayerKill", Leet_OnPlayerKill},
	{"Leet_OnRoundEnd", Leet_OnRoundEnd},
	{"Leet_GetBalance", Leet_GetBalance},
	{NULL, NULL},
};

void Leet::SDK_OnAllLoaded() {
	leetApi = new LeetApi();
	sharesys->AddNatives(myself, LeetNatives);
}

void Leet::SDK_OnUnload() {
	delete(leetApi);
}
