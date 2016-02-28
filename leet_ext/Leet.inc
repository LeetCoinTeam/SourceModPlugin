#if defined _Leet_included

  #endinput

#endif

#define _Leet_included

/**
 * Digests a string with a given key.
 *
 * @param key	Key for hmac.
 * @param data  Data (string) to digest.
 * @param buffer Buffer to put digest into.
 * @param maxlen Maximum length of the buffer.
 * @return	The hex digest of the string passed in.
 */
native bool:digest_string_with_key(const String:key[], const String:data[], String:buffer[], int maxlen);

native bool:digest_string_with_key_length(const String:key[], const String:data[], String:buffer[], int maxlen, int string_length);

native int:append_string(String:dest[], int str_offset, String:source[], int cpylen);

native int:url_escape(String:dest[], int max_length, String:source[]);
