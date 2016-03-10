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

void GetClientInformation(const std::string steam64) {
	bool allowed = leetApi->activatePlayer(steam64);
	return;
}

void DeactivateClient(const std::string steam64) {
	bool allowed = leetApi->deactivatePlayer(steam64);
	return;
}

void ReportKill(const std::string killer64, const std::string victim64) {
	bool kick_victim = leetApi->onPlayerKill(killer64, victim64);
	return;
}

cell_t Leet_OnPluginLoad(IPluginContext *pContext, const cell_t *params) {
	char *api_key, *api_secret;
	pContext->LocalToString(params[1], &api_key);
	pContext->LocalToString(params[2], &api_secret);
	std::string key(api_key);
	std::string secret(api_secret);
	std::cout << "Created Thread." << std::endl;
	auto result = pool.enqueue(GetServerInformation, key, secret);
	return 0;
}



cell_t Leet_OnClientConnected(IPluginContext *pContext, const cell_t *params) {
	int player = (unsigned int)params[1];

	IGamePlayer *pPlayer = playerhelpers->GetGamePlayer(player);

	std::ostringstream steam64_stream;
	steam64_stream << pPlayer->GetSteamId64();

	std::string steam64(steam64_stream.str());
	if(steam64.length() <= 1) {
		std::cout << "Tryed to register bot or entity on Leet." << std::endl;
		return leetApi->getAllowUnauthorized();
	}
	//IPlugin *pPlugin = plsys->FindPluginByContext(pContext->GetContext());
	//if(!pPlugin)
	//	return pContext->ThrowNativeError("Plugin not found.");

	/*IPluginFunction *pFunction = pPlugin->GetBaseContext()->GetFunctionById(params[2]);
	IChangeableForward *forward = forwards->CreateForwardEx(NULL, ET_Ignore, 2, NULL, Param_Cell);
	Forward->AddFunction(pFunction);
	forward->PushCell(allowed);
	forward->Execute(NULL);
	forwards->ReleaseForward(forward);*/
	pool.enqueue(GetClientInformation, steam64);
	return 0;
}


cell_t Leet_OnClientDisconnected(IPluginContext *pContext, const cell_t *params) {
	int player = (unsigned int)params[1];

	IGamePlayer *pPlayer = playerhelpers->GetGamePlayer(player);

	std::ostringstream steam64_stream;
	steam64_stream << pPlayer->GetSteamId64();

	std::string steam64(steam64_stream.str());
	if(steam64.length() <= 1) {
		std::cout << "Tryed to register bot or entity on Leet." << std::endl;
		return leetApi->getAllowUnauthorized();
	}

	pool.enqueue(DeactivateClient, steam64);
	return 0;
}

cell_t Leet_PlayerKilled(IPluginContext *pContext, const cell_t *params) {
	char *killer64, *killer_weapon, *victim64, *victim_weapon;
	pContext->LocalToString(params[1], &killer64);
	pContext->LocalToString(params[2], &victim64);

	std::string killer64_string(killer64);
	std::string victim64_string(victim64);

	pool.enqueue(ReportKill, killer64_string, victim64_string);

	return 0;
}

cell_t Leet_OnRoundEnd(IPluginContext *pContext, const cell_t *params) {
	leetApi->submitMatchResults();

	/*if (this->pCompletedForward == NULL || this->pCompletedForward->GetFunctionCount() == 0)
		return;

	this->pCompletedForward->PushCell(this->handle);
	this->pCompletedForward->PushCell(bFailed);
	this->pCompletedForward->PushCell(pRequest->m_bRequestSuccessful);
	this->pCompletedForward->PushCell(pRequest->m_eStatusCode);
	this->pCompletedForward->PushCell(pRequest->m_ulContextValue >> 32);
	this->pCompletedForward->PushCell((pRequest->m_ulContextValue & 0x00000000FFFFFFFF));
	this->pCompletedForward->Execute(NULL); */

	return 0;
}

const sp_nativeinfo_t LeetNatives[] = 
{
	{"Leet_OnPluginLoad", Leet_OnPluginLoad},
	{"Leet_OnClientConnected", Leet_OnClientConnected},
	{"Leet_OnClientDisconnected", Leet_OnClientDisconnected},
	{"Leet_PlayerKilled", Leet_PlayerKilled},
	{"Leet_OnRoundEnd", Leet_OnRoundEnd},
	{NULL, NULL},
};

void Leet::SDK_OnAllLoaded() {
	leetApi = new LeetApi();
	sharesys->AddNatives(myself, LeetNatives);
}

void Leet::SDK_OnUnload() {
	delete(leetApi);
}
