#include "extension.h"

/**
 * @file extension.cpp
 */
LeetApi *leetApi;
Leet g_Leet;		/**< Global singleton for extension's main interface */
// *g_pSteamWorks = NULL;

SMEXT_LINK(&g_Leet);

cell_t digest_string_with_key_length(IPluginContext *pContext, const cell_t *params) {
	char *key, *data, *buffer;
	pContext->LocalToString(params[1], &key);
	pContext->LocalToString(params[2], &data);
	pContext->LocalToString(params[3], &buffer);
	unsigned int buffer_size = (unsigned int)params[4];
	unsigned int str_len = (unsigned int)params[5];
	unsigned char* digest;
	digest = HMAC(EVP_sha512(), key, strlen(key), (unsigned char*)data, str_len, NULL, NULL);

	for(int i = 0; i < 64; i++) {
		sprintf(&buffer[i*2], "%02x", (unsigned int)digest[i]);	
	}

	size_t bytes;
	pContext->StringToLocalUTF8(params[3], params[4], buffer, &bytes);
	return 1;
}

cell_t Leet_PlayerKilled(IPluginContext *pContext, const cell_t *params) {
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
	{"digest_string_with_key_length", digest_string_with_key_length},
	{NULL, NULL},
};

void Leet::SDK_OnAllLoaded() {
	leetApi = new LeetApi();
	sharesys->AddNatives(myself, LeetNatives);
}

void Leet::SDK_OnUnload() {
	delete(leetApi);
}
