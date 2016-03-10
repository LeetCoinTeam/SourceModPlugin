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
	if(!allowed) {
		pPlayer->Kick("Please go to Leet.gg and register for this server. You are currently not authorized.");
		std::cout << "Kicked client: " << steam64 << " for not authing." << std::endl;
	}
	return;
}

void DeactivateClient(const std::string steam64, IGamePlayer *pPlayer) {
	bool allowed = leetApi->deactivatePlayer(steam64);
	if(!allowed) {
		pPlayer->Kick("Please go to Leet.gg and register for this server. You are currently not authorized.");
		std::cout << "Kicked client: " << steam64 << " for not authing." << std::endl;
	}
	return;
}

void ReportKill(IGamePlayer *pKiller, IGamePlayer *pVictim) {
	std::ostringstream killer_stream, victim_stream;

	killer_stream << pKiller->GetSteamId64();
	victim_stream << pVictim->GetSteamId64();

	//IPlayerInfo *iKiller = pKiller->GetPlayerInfo();
	//IPlayerInfo *iVictim = pVictim->GetPlayerInfo();

	//std::string killer_weapon(iKiller->GetWeaponName());
	//std::string victim_weapon(iVictim->GetWeaponName());
	std::string killer_weapon("N/A");
	std::string victim_weapon("N/A");

	bool kick_victim = leetApi->onPlayerKill(killer_stream.str(), killer_weapon, victim_stream.str(), victim_weapon);

	if(kick_victim) {
		pVictim->Kick("Your balance is too low. Go to Leet.gg and re-up.");
	}
	return;
}

void submitMatchResults() {
	std::list<std::string> kick_players = leetApi->submitMatchResults();
	// We're in a different thread here and we released the lock.
	// TODO: Break these out into two loops. Store the vector if IGamePlayers then do the search.
	for(auto iter = kick_players.begin(); iter != kick_players.end(); ++iter) {
		for(int i = 0; i < playerhelpers->GetMaxClients(); i++) {
			IGamePlayer *pPlayer = playerhelpers->GetGamePlayer(i);
			if(pPlayer && pPlayer->IsConnected() && !pPlayer->IsFakeClient() && pPlayer->IsAuthorized()) {
				std::ostringstream steam64_stream;
				steam64_stream << pPlayer->GetSteamId64();
				if(steam64_stream.str() == *iter) {
					std::cout << "Deauthed: " << steam64_stream.str() << std::endl;
					pPlayer->Kick("Deauthorized by Leet.gg. Please go to leet.gg and re-register to play.");
					break;
				}
			}
		}
	}
}

cell_t Leet_OnPluginLoad(IPluginContext *pContext, const cell_t *params) {
	char *api_key, *api_secret;
	pContext->LocalToString(params[1], &api_key);
	pContext->LocalToString(params[2], &api_secret);
	std::string key(api_key);
	std::string secret(api_secret);
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
	if(steam64.length() <= 1 || !pPlayer->IsConnected() || pPlayer->IsFakeClient() || !pPlayer->IsAuthorized()) {
		std::cout << "Tryed to register bot or entity on Leet." << std::endl;
		if(leetApi->getAllowUnauthorized()) {
			std::cout << "Goodbye Bot :)" << std::endl;
			pPlayer->Kick("Goodbye Bot :)");
		}
		return 0;
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
		std::cout << "Tryed to unregister bot or entity on Leet." << std::endl;
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

	pool.enqueue(ReportKill, pKiller, pVictim);

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

	gamehelpers->TextMsg(player, TEXTMSG_DEST_CHAT, player_stream.str().c_str());

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
