#ifndef _LEET_API
#define _LEET_API

#include <algorithm>
#include <time.h>
#include <string>
#include <sstream>
#include <iostream>
#include <curlpp/cURLpp.hpp>
#include <curlpp/Easy.hpp>
#include <curlpp/Options.hpp>
#include <mutex>
#include <openssl/hmac.h>
#include <openssl/evp.h>
#include <json/json.h>
#include <iomanip>

class LeetApi
{
	public:
  		const std::string api_test = "http://apitest-dot-1337coin.appspot.com";
  		const std::string get_server_info = "/api/get_server_info";
		const std::string activate_player = "/api/activate_player";
		const std::string put_match_results = "/api/put_match_results";
		const std::string issue_award = "/api/issue_award";
		const std::string deactivate_player = "/api/deactivate_player";
        const std::string content_type_header = "Content-Type: application/x-www-form-urlencoded";

		LeetApi();
        LeetApi(const std::string api_key, const std::string api_secret);
		~LeetApi();
        void setApiKey(const std::string api_key);
        void setApiSecret(const std::string api_secret);
        std::string digestString(const std::string undigested_string);
        std::string urlEscape(const std::string unencoded_url);
        bool getServerInformation();
        bool activatePlayer(const std::string platform_id);
        bool deactivatePlayer(const std::string platform_id);
        std::list<std::string> submitMatchResults();
        bool onPlayerKill(const std::string killer_platform_id, const std::string victim_platform_id);
        bool getAllowUnauthorized();
        uint64_t getBalance(std::string platform_id);

    private:
    
        class ServerInformation {
            public:
                uint64_t minimum_btc_hold;
                bool death_penalty;
                bool allow_unauthorized;
                uint64_t admission_fee;
                float server_rake_percentage;
                std::string api_version;
                uint64_t increment_btc;
                float leetcoin_rake_percentage;
        };
    
  		class Player {
            public:
                uint64_t btc_hold;
                std::string name;
                std::string platform_id;
                std::string key;
                bool previously_active;
                bool authorized;
                float currency_conversion;
                std::string currency_display;
                int kills;
                int deaths;
                int player_rank;
                std::string weapon;
                bool operator==(const Player& player);
                Json::Value to_json();
  		};

  		std::string api_key_;
  		std::string api_secret_;
        std::mutex player_list_guard_;
        std::string keyHeader();
        std::list<std::string> generateHeaders(const std::string param_string);
  		std::list<LeetApi::Player> players;
        LeetApi::ServerInformation server_information_;
        std::string sendRequest(std::list<std::string> headers, std::string post_body, std::string url);
        void calculateRank(LeetApi::Player *killer, LeetApi::Player *victim);

};

#endif