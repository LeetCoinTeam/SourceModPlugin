#include "LeetApi.h"


LeetApi::LeetApi() {
    return;
}

LeetApi::LeetApi(const std::string api_key, const std::string api_secret) {
    this->api_secret_ = api_secret;
    this->api_key_ = api_key;
}

LeetApi::~LeetApi() {
    return;
}

void LeetApi::setApiKey(const std::string api_key) {
    this->api_key_ = api_key;
    return;
}

void LeetApi::setApiSecret(const std::string api_secret) {
    this->api_secret_ = api_secret;
    return;
}

std::string LeetApi::digestString(const std::string undigested_string) {
    std::stringstream digestedstream;
    
    unsigned char * digest = HMAC(EVP_sha512(), this->api_secret_.c_str(), this->api_secret_.length(), (unsigned char*)undigested_string.c_str(), undigested_string.length(), NULL, NULL);
    
    for(int i = 0; i < 64; i++) {
        char buffer[3];
        sprintf(&buffer[0], "%02x", (unsigned int)digest[i]);
        digestedstream << buffer;
    }
    
    return digestedstream.str();
}

std::string LeetApi::keyHeader() {
    std::stringstream header;
    header << "Key: " << this->api_key_;
    return header.str();
}

bool LeetApi::activatePlayer(const std::string platform_id) {
    std::stringstream post_body;
    time_t seconds_past_epoch = time(0);
    post_body << "nonce=" << seconds_past_epoch << "&platformid=" << platform_id;
    
    auto response_body = this->sendRequest(this->generateHeaders(post_body.str()), post_body.str(), this->activate_player);
    
    Json::Value json;
    Json::Reader json_reader;
    
    if(!json_reader.parse(response_body, json, false)) {
        std::cout << "Failed to parse json from server." << std::endl;
        return this->server_information_.allow_unauthorized;
    }
    
    LeetApi::Player player;
    if(json["authorization"].asBool() && json["player_authorized"].asBool()) {
        player = {
            json["player_btchold"].asUInt64(),
            json["player_name"].asString(),
            json["player_platformid"].asString(),
            json["player_key"].asString(),
            json["player_previously_active"].asBool(),
            json["player_authorized"].asBool(),
            std::stof(json["default_currency_conversion"].asString()),
            json["default_currency_display"].asString(),
            0,
            0,
            json["player_rank"].asInt()
        };
        
        std::lock_guard<std::mutex> lock(this->player_list_guard_);

        // Double check this
        auto found_player = std::find(this->players.begin(), this->players.end(), player);

        if(found_player == this->players.end()) {
            // subtract admission fee
            player.btc_hold -= this->server_information_.admission_fee;
            this->players.push_back(player);
        }
        else {
            std::cout << "Player already in player list." << std::endl;
            found_player->authorized = player.authorized;
            found_player->previously_active = player.previously_active;
        }
    } else {
        std::cout << "Failed to authorize with server." << std::endl;
        return this->server_information_.allow_unauthorized;
    }
    
    return true;
}

bool LeetApi::deactivatePlayer(const std::string platform_id) {
    std::stringstream post_body;
    time_t seconds_past_epoch = time(0);
    post_body << "nonce=" << seconds_past_epoch << "&platformid=" << platform_id;
    
    auto response_body = this->sendRequest(this->generateHeaders(post_body.str()), post_body.str(), this->deactivate_player);

    Json::Value json;
    Json::Reader json_reader;
    
    if(!json_reader.parse(response_body, json, false)) {
        std::cout << "Failed to parse json from server." << std::endl;
        return this->server_information_.allow_unauthorized;
    }

    std::lock_guard<std::mutex> lock(this->player_list_guard_);

    if(json["authorization"].asBool()) {
        auto player = std::find_if(this->players.begin(), this->players.end(), [platform_id] (LeetApi::Player const& p) { return p.platform_id == platform_id; });
        
        if(player != this->players.end()) {
            player->key = json["player_key"].asString();
            player->previously_active = json["player_previously_active"].asBool();
            player->authorized = json["player_authorized"].asBool();
        } else {
            std::cout << "Could not deauth player because they weren't found in the authorized list." << std::endl;
        }
        
    } else {
        std::cout << "Failed to authorize with server." << std::endl;
        return this->server_information_.allow_unauthorized;
    }
    
    return true;
}

std::list<std::string> LeetApi::submitMatchResults() {
    std::list<std::string> kick_users;
    std::stringstream post_body;
    time_t seconds_past_epoch = time(0);
    post_body << "nonce=" << seconds_past_epoch << "&map_title=Testerino";
    
    std::lock_guard<std::mutex> lock(this->player_list_guard_);
    // If there is no player list let's just return, TODO: this doesn't scale well.
    if(this->players.size() == 0) {
        return kick_users;
    }

    Json::Value player_dict;
    for(auto iter = this->players.begin(); iter != this->players.end(); ++iter)
        player_dict.append(iter->to_json());
    
    post_body << "&player_dict_list=" << this->urlEscape(player_dict.toStyledString());
    
    auto response_body = this->sendRequest(this->generateHeaders(post_body.str()), post_body.str(), this->put_match_results);

    Json::Value json;
    Json::Reader json_reader;
    
    if(!json_reader.parse(response_body, json, false)) {
        std::cout << "Failed to parse json from server when submitting match results." << std::endl;
        return kick_users;
    }

    // TODO: This needs testing
    if(json["authorization"].asBool()) {
        for (auto itr : json["playersToKick"])
            kick_users.push_back(itr.asString());
    }
    
    for(auto iter = this->players.begin(); iter != this->players.end(); ++iter) {
        iter->kills = 0;
        iter->deaths = 0;
        // Removed deauth / unauthed players
        if(!iter->authorized) {
            std::cout << "Removed " << iter->name << " from the server." << std::endl;
            iter = this->players.erase(iter);
        }
    }

    return kick_users;
}

Json::Value LeetApi::Player::to_json() {
    Json::Value value(Json::objectValue);
    value["platformID"] = this->platform_id;
    value["deaths"] = this->deaths;
    value["kills"] = this->kills;
    value["name"] = this->name;
    value["rank"] = this->player_rank;
    if(this->weapon.length() == 0)
        value["weapon"] = "N/A";
    else
        value["weapon"] = this->weapon;
    return value;
}

std::list<std::string> LeetApi::generateHeaders(const std::string param_string) {
    std::list<std::string> headers;
    headers.push_back(this->content_type_header);
    headers.push_back(this->keyHeader());
    std::stringstream sign;
    sign << "Sign: " << this->digestString(param_string);
    headers.push_back(sign.str());
    
    return headers;
}

bool LeetApi::getServerInformation() {
    std::stringstream post_body;
    time_t seconds_past_epoch = time(0);
    post_body << "nonce=" << seconds_past_epoch;
    
    auto response_body = this->sendRequest(this->generateHeaders(post_body.str()), post_body.str(), this->get_server_info);
    
    Json::Value json;
    Json::Reader json_reader;
    
    if(!json_reader.parse(response_body, json, false)) {
        std::cout << "Failed to parse json from server." << std::endl;
        return false;
    }
    
    if(json["authorization"].asBool()) {
        this->server_information_ = {
            json["minimumBTCHold"].asUInt64(),
            !json["no_death_penalty"].asBool(),
            json["allow_non_authorized_player"].asBool(),
            json["admissionFee"].asUInt64(),
            json["serverRakeBTCPercentage"].asFloat(),
            json["api_version"].asString(),
            json["incrementBTC"].asUInt64(),
            json["leetcoinRakePercentage"].asFloat()
        };
    } else {
        std::cout << "Failed to authorize with server." << std::endl;
        return false;
    }
    
    return true;
}

bool LeetApi::onPlayerKill(const std::string killer_platform_id, const std::string killer_weapon, const std::string victim_platform_id, const std::string victim_weapon) {
    // Critical section.
    std::lock_guard<std::mutex> lock(this->player_list_guard_);

    // Find player that killed from player list
    auto killer = std::find_if(this->players.begin(), this->players
        .end(), [killer_platform_id] (LeetApi::Player const& p) { return p.platform_id == killer_platform_id; });
    if(killer == this->players.end()) {
        std::cout << "Couldn't find the killer in the player list." << std::endl;
    }

    // Find player that died in player list
    auto victim = std::find_if(this->players.begin(), this->players.end(), [victim_platform_id] (LeetApi::Player const& p) { return p.platform_id == victim_platform_id; });
    if(victim == this->players.end()) {
        std::cout << "Couldn't find the killer in the player list." << std::endl;
    }

    if(!victim->authorized) {
        std::cout << "Victim not authorized, kill not recorded." << std::endl;
        return 0; 
    }

    if(!killer->authorized) {
        std::cout << "Killer not authorized, kill not recorded." << std::endl;
        return 0; 
    }

    killer->weapon = killer_weapon;
    victim->weapon = victim_weapon;

    // Increment and decrement kills and deaths respectively
    killer->kills++;
    victim->deaths++;

    killer->btc_hold += (-1.0 * (this->server_information_.server_rake_percentage + this->server_information_.leetcoin_rake_percentage) * this->server_information_.increment_btc)
        + this->server_information_.increment_btc;

    if(this->server_information_.death_penalty)
        victim->btc_hold -= this->server_information_.increment_btc;

    // ELO
    this->calculateRank(&*killer, &*victim);

    // TODO: Kick if necessary and dauth
    return (victim->btc_hold < this->server_information_.minimum_btc_hold);
}

uint64_t LeetApi::getBalance(std::string platform_id) {
    // Critical section.
    std::lock_guard<std::mutex> lock(this->player_list_guard_);

    auto player = std::find_if(this->players.begin(), this->players
        .end(), [platform_id] (LeetApi::Player const& p) { return p.platform_id == platform_id; });

    if(player == this->players.end()) {
        std::cout << "Couldn't find the killer in the player list." << std::endl;
        return 0;
    }

    return player->btc_hold;
}


std::string LeetApi::sendRequest(std::list<std::string> headers, std::string post_body, std::string url) {
    std::cout << "post body: " << post_body << std::endl;
    std::ostringstream os;
    curlpp::options::WriteStream ws(&os);
    try {
        curlpp::Cleanup clean;
        curlpp::Easy request;
        request.setOpt<curlpp::options::Url>(this->api_test + url);
        request.setOpt(new curlpp::options::Verbose(false));
        request.setOpt(new curlpp::options::HttpHeader(headers));
        request.setOpt(new curlpp::options::PostFields(post_body));
        request.setOpt(new curlpp::options::PostFieldSize(post_body.length()));
        request.setOpt(ws);
        request.perform();
    }
    catch(curlpp::RuntimeError &e) {
        std::cout << e.what() << std::endl;
    }
    
    catch(curlpp::LogicError &e) {
        std::cout << e.what() << std::endl;
    }
    
    // TODO: Catch when there's not a 200 from the server, auth failure
    std::cout << "response body: " << os.str() << std::endl;
    return os.str();
}

std::string LeetApi::urlEscape(const std::string unencoded_url) {
    const std::string unreserved = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.~";
    std::string escaped = "";
    for(size_t i=0; i < unencoded_url.length(); i++) {
        if (unreserved.find_first_of(unencoded_url[i]) != std::string::npos) {
            escaped.push_back(unencoded_url[i]);
        } else {
            if(' ' == unencoded_url[i])
                escaped.append("+");
            else {
                escaped.append("%");
                char buf[3];
                sprintf(buf, "%.2X", unencoded_url[i]);
                escaped.append(buf);
            }
        }
    }
    return escaped;
}

void LeetApi::calculateRank(LeetApi::Player *killer, LeetApi::Player *victim) {
    std::cout << "Old killer rank: " << killer->player_rank << " old victim rank: " << victim->player_rank;

    int difference = killer->player_rank - victim->player_rank;
    double exponent = (difference*-1.0)/400.00;
    double odds = (1/(1 + std::pow(10, exponent)));

    int k;
    if(killer->player_rank < 2100)
        k = 32;
    else if(killer->player_rank >= 2100 && killer->player_rank < 2400)
        k = 24;
    else
        k = 16;

    int new_winner_rank = std::round(killer->player_rank + (k * (1 - odds)));

    if(this->server_information_.death_penalty)
        victim->player_rank -= (new_winner_rank - killer->player_rank);
    
    if(victim->player_rank < 1)
        victim->player_rank = 1;

    killer->player_rank = new_winner_rank;

    std::cout << "New killer rank: " << killer->player_rank << " new victim rank: " << victim->player_rank;
    return;
}

bool LeetApi::Player::operator==(const Player& player) {
    if (this->platform_id == player.platform_id)
        return true;
    return false;
}

bool LeetApi::getAllowUnauthorized() {
    return this->server_information_.allow_unauthorized;
}

/*int main ()
{
    LeetApi *leetApi = new LeetApi("LXtZ4O-4FmFjw-OxTggA-47gEtb", "gUNXh9MVyn5RpDXbP4kTEl91IxdJRM");
    leetApi->getServerInformation();
    leetApi->activatePlayer("76561197963127789");
    leetApi->submitMatchResults();
    leetApi->deactivatePlayer("76561197963127789");
    return 0;
    // g++ -std=c++11 -I/usr/local/include -I/usr/include/jsoncpp LeetApi.cpp -L/usr/local/lib -ljsoncpp -lcurlpp -lcurl -lssl -lcrypto -o leetapi

}*/

