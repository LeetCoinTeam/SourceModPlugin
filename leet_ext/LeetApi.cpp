#include "leetapi.h"


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
    
    std::cout << response_body << std::endl;
    
    Json::Value json;
    Json::Reader json_reader;
    
    if(!json_reader.parse(response_body, json, false)) {
        std::cout << "Failed to parse json from server." << std::endl;
        return this->serverInformation.allow_unauthorized;
    }
    
    if(json["authorization"].asBool()) {
        LeetApi::Player player = {
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
        
        // Double check this bullshit
        if(std::find(this->players.begin(), this->players.end(), player) == this->players.end())
            this->players.push_back(player);
        else
            std::cout << "Player already in player list." << std::endl;
    } else {
        std::cout << "Failed to authorize with server." << std::endl;
        return this->serverInformation.allow_unauthorized;
    }
    
    return true;
}

bool LeetApi::deactivatePlayer(const std::string platform_id) {
    std::stringstream post_body;
    time_t seconds_past_epoch = time(0);
    post_body << "nonce=" << seconds_past_epoch << "&platformid=" << platform_id;
    
    auto response_body = this->sendRequest(this->generateHeaders(post_body.str()), post_body.str(), this->deactivate_player);
    
    std::cout << response_body << std::endl;

    Json::Value json;
    Json::Reader json_reader;
    
    if(!json_reader.parse(response_body, json, false)) {
        std::cout << "Failed to parse json from server." << std::endl;
        return this->serverInformation.allow_unauthorized;
    }
    
    if(json["authorization"].asBool()) {
        auto player = std::find_if(this->players.begin(), this->players.end(), [platform_id] (LeetApi::Player const& p) { return p.platform_id == platform_id; });
        
        if(player != this->players.end()) {
            player->key = json["player_key"].asString();
            player->previously_active = json["player_previously_active"].asBool();
            player->authorized = json["player_authorized"].asBool();
        } else {
            std::cout << "Could not find player in the list." << std::endl;
        }
        
    } else {
        std::cout << "Failed to authorize with server." << std::endl;
        return this->serverInformation.allow_unauthorized;
    }
    
    return true;
}

bool LeetApi::submitMatchResults() {
    std::stringstream post_body;
    time_t seconds_past_epoch = time(0);
    post_body << "nonce=" << seconds_past_epoch << "&map_title=Testerino";
    
    Json::Value player_dict;
    for(auto iter = this->players.begin(); iter != this->players.end(); ++iter)
        player_dict.append(iter->to_json());
    
    post_body << "&player_dict_list=" << this->urlEscape(player_dict.toStyledString());
    
    auto response_body = this->sendRequest(this->generateHeaders(post_body.str()), post_body.str(), this->put_match_results);
    
    std::cout << response_body << std::endl;
    
    return true;
}

Json::Value LeetApi::Player::to_json() {
    Json::Value value(Json::objectValue);
    value["platformID"] = this->platform_id;
    value["deaths"] = this->deaths;
    value["kills"] = this->kills;
    value["name"] = this->name;
    value["rank"] = this->player_rank;
    value["weapon"] = "N/A";
    return value;
}

std::list<std::string> LeetApi::generateHeaders(const std::string param_string) {
    // TODO: Add nonce
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
        this->serverInformation = {
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

std::string LeetApi::sendRequest(std::list<std::string> headers, std::string post_body, std::string url) {
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

bool LeetApi::Player::operator==(const Player& player) {
    if (this->platform_id == player.platform_id)
        return true;
    return false;
}

/*int main ()
{
    LeetApi *leetApi = new LeetApi("LXtZ4O-4FmFjw-OxTggA-47gEtb", "gUNXh9MVyn5RpDXbP4kTEl91IxdJRM");
    leetApi->getServerInformation();
    leetApi->activatePlayer("76561197963127789");
    leetApi->submitMatchResults();
    leetApi->deactivatePlayer("76561197963127789");
    return 0;
}*/

