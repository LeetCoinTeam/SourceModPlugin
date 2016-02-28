#include "extension.h"

/**
 * @file extension.cpp
 */

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

cell_t append_string(IPluginContext *pContext, const cell_t *params) {
	// There's no saftey in this, going to assume the sizes are ok.
	// Could segfault anytime.
	char *dest, *source;
	unsigned int offset, length, total_len;
	pContext->LocalToString(params[1], &dest);
	offset = (unsigned int)params[2];
	pContext->LocalToString(params[3], &source);
	length = (unsigned int)params[4];

	total_len = offset + length;

	char *begin = (dest + offset);
	for(unsigned int i = 0; i < length; i++) {
		begin[i] = source[i];
	}
	// Probably need to document this.
	begin[length] = '\0';

	return total_len;
};

cell_t url_escape(IPluginContext *pContext, const cell_t *params) {
	char *dest, *source;
	pContext->LocalToString(params[1], &dest);
	unsigned int max_length = (unsigned int)params[2];
	pContext->LocalToString(params[3], &source);

	const std::string unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~";
	std::string escaped = "";
	for(size_t i=0; i < strlen(source); i++) {
		if (unreserved.find_first_of(source[i]) != std::string::npos) {
			escaped.push_back(source[i]);
		} else {
			if(' ' == source[i])
				escaped.append("+");
			else {
				escaped.append("%");
				char buf[3];
				sprintf(buf, "%.2X", source[i]);
				escaped.append(buf);
			}
		}
	}
	if(escaped.length() < max_length) {
		memcpy(dest, escaped.c_str(), escaped.length());
	} else {
		printf("url_escape: buffer < encoded length.");
	}
	return escaped.length();
}

const sp_nativeinfo_t LeetNatives[] = 
{
	{"digest_string_with_key", digest_string_with_key},
	{"digest_string_with_key_length", digest_string_with_key_length},
	{"append_string", append_string},
	{"url_escape", url_escape},
	{NULL, NULL},
};

void Leet::SDK_OnAllLoaded() {
	sharesys->AddNatives(myself, LeetNatives);
}
