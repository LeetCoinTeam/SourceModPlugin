#include "extension.h"

/**
 * @file extension.cpp
 */
LeetApi *leetApi;
Leet g_Leet;		/**< Global singleton for extension's main interface */
// *g_pSteamWorks = NULL;

SMEXT_LINK(&g_Leet);

cell_t Leet_OnPluginLoad(IPluginContext *pContext, const cell_t *params) {
	char *api_key, *api_secret;
	pContext->LocalToString(params[1], &api_key);
	pContext->LocalToString(params[2], &api_secret);
	std::string key(api_key);
	std::string secret(api_secret);
	leetApi->setApiKey(key);
	leetApi->setApiSecret(secret);
	return leetApi->getServerInformation();
}

cell_t Leet_OnClientConnected(IPluginContext *pContext, const cell_t *params) {
	char *steam64;
	pContext->LocalToString(params[1], &steam64);
	std::string steam64_string(steam64);
	if(steam64_string.length() == 0)
		return 0;
	return leetApi->activatePlayer(steam64_string);
}

cell_t Leet_PlayerKilled(IPluginContext *pContext, const cell_t *params) {
	//pContext->LocalToString(params[3], &buffer);
	//unsigned int buffer_size = (unsigned int)params[4];
	/*IPlugin *pPlugin;
	if (params[5] == BAD_HANDLE)
	{
		pPlugin = plsys->FindPluginByContext(pContext->GetContext());
	} else {
		HandleError err;
		pPlugin = plsys->PluginFromHandle(params[5], &err);

		if (!pPlugin)
		{
			return pContext->ThrowNativeError("Plugin handle %x is invalid (error %d)", params[5], err);
		}
	}

	if (params[2] > 0)
	{
		if (pRequest->pCompletedForward == NULL)
		{
			pRequest->pCompletedForward = forwards->CreateForwardEx(NULL, ET_Ignore, 6, NULL, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell, Param_Cell);
		}

		IPluginFunction *pFunction = pPlugin->GetBaseContext()->GetFunctionById(params[2]);

		if (!pFunction)
		{
			return pContext->ThrowNativeError("Invalid function id (%X)", params[2]);
		}

		pRequest->pCompletedForward->AddFunction(pFunction);
	}*/
	return 1;
}

const sp_nativeinfo_t LeetNatives[] = 
{
	{"Leet_OnPluginLoad", Leet_OnPluginLoad},
	{"Leet_OnClientConnected", Leet_OnClientConnected},
	{NULL, NULL},
};

void Leet::SDK_OnAllLoaded() {
	leetApi = new LeetApi();
	sharesys->AddNatives(myself, LeetNatives);
}

void Leet::SDK_OnUnload() {
	delete(leetApi);
}
