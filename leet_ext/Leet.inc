#if defined _Leet_included

  #endinput

#endif

#define _Leet_included

native bool:Leet_OnPluginLoad(const String:server_api_key[], const String:server_api_secret[]);

/**
 * Authenticates a client with Leet on connect.
 *
 * @param steam64
 * @return	Whether or not the client was authorized.
 */
native bool:Leet_OnClientConnected(int player);

native bool:Leet_OnClientDisconnected(int player);

native bool:Leet_OnPlayerKill(const int killer, const int victim);

native bool:Leet_OnRoundEnd();
