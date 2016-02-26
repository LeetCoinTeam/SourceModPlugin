#include "extension.h"

/**
 * @file extension.cpp
 */

Leet g_Leet;		/**< Global singleton for extension's main interface */

SMEXT_LINK(&g_Leet);

cell_t digest_string_with_key(IPluginContext *pContext, const cell_t *params) {
	char *key, *data, *buffer;
	pContext->LocalToString(params[1], &key);
	pContext->LocalToString(params[2], &data);
	pContext->LocalToString(params[3], &buffer);
	unsigned int buffer_size = (unsigned int)params[4];
	unsigned char* digest;
	digest = HMAC(EVP_sha512(), key, strlen(key), (unsigned char*)data, strlen(data), NULL, NULL);

	for(int i = 0; i < 64; i++) {
		sprintf(&buffer[i*2], "%02x", (unsigned int)digest[i]);	
	}

	size_t bytes;
	pContext->StringToLocalUTF8(params[3], params[4], buffer, &bytes);
	return 1;
}

const sp_nativeinfo_t LeetNatives[] = 
{
	{"digest_string_with_key", digest_string_with_key},
	{NULL, NULL},
};

void Leet::SDK_OnAllLoaded() {
	sharesys->AddNatives(myself, LeetNatives);
}
