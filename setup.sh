#!/usr/bin/bash

bold=$(tput bold)
normal=$(tput sgr0)
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

git submodule update --init --recursive

if [ "$?" -ne 0 ]; then 
    echo "Git submodule update failed. Exiting script"
    exit 1;
fi 

generate_password() {
    tr -dc '[:alnum:]' < /dev/urandom | head -c 15
}

calc_sha256() {
    echo -n "$1" | sha256sum | cut -d " " -f1
}

copy_file_if_not_exist() {
    folder=$1
    original_file=$2
    copied_file=$3

    if ! [ -f "$folder/$copied_file" ]; then
        if ! [ -w "$folder" ]; then 
            echo "No write access to the $folder folder. Please change the permissions to that folder." 
            exit 1
        fi 

        echo -n "$copied_file not found. Copying $folder/$original_file"
        cp "$folder/$original_file" "$folder/$copied_file"
        echo -e "... ${GREEN}done ${NC}"
        echo
    fi
}

replace_line_in_file() {
    file=$1
    original_line=$2
    new_line=$3
    type=$4

    if ! grep -Ei "$original_line" < "$file" 2>&1 > /dev/null; then
        echo "Cannot copy $type into $file. Please do so manually."
        exit 1
    fi
    echo -n "Copying $type into $file"
    sed -i -e "s/$original_line/$new_line/" $file
    echo -e "... ${GREEN}done${NC}"
    # echo
}

echo -e "${RED}========== Lots of passwords will be generated by this script randomly. Make sure you note them down! ==========${NC}"
# =============== Set up MySQL===============
echo
echo -e "${CYAN}Setting up MySQL${NC}"
echo ======================================================
copy_file_if_not_exist "mysql" ".env.template" ".env"

db_pass=$(generate_password)
echo "Generated MySQL user (MOCBOT_API) password: ${bold}$db_pass${normal}"
db_root_pass=$(generate_password)
echo "Generated MySQL root user password: ${bold}$db_root_pass${normal}"
echo


replace_line_in_file "mysql/.env" "^MYSQL_PASSWORD.*$" "MYSQL_PASSWORD=$db_pass" "MySQL user password"
replace_line_in_file "mysql/.env" "^MYSQL_ROOT_PASSWORD.*$" "MYSQL_ROOT_PASSWORD=$db_root_pass" "MySQL root password"

# =============== Set up API env ===============
echo
echo -e "${CYAN}Setting up MOCBOT API${NC}"
echo ======================================================
copy_file_if_not_exist "api" ".env.template" ".env"

mocbot_api_key=$(generate_password)
echo "Generated MOCBOT API key: ${bold}$mocbot_api_key${normal}"
echo

mocbot_api_key_hash=$(calc_sha256 "$mocbot_api_key")
replace_line_in_file "api/.env" "DB_PASS.*$" "DB_PASS = $db_pass" "MySQL user password"

# =============== Script to insert API key hash ===============
if [ -w "mysql/data" ]; then 
    echo -n "Creating an SQL script to add MOCBOT API key hash into the database"
    echo "INSERT INTO APIKeys VALUES ('MOCBOT_API', \"$mocbot_api_key_hash\");" > ./mysql/data/sql-db-add-info.sql
    echo -e "... ${GREEN}done${NC}"
    echo
else 
    echo "No write access to mysql/data folder. Please change the permissions to that folder."
    exit 1 
fi

# =============== Set up Lavalink config ===============
echo
echo -e "${CYAN}Setting up Lavalink${NC}"
echo ======================================================
copy_file_if_not_exist "lavalink" "application.template.yml" "application.yml"

lavalink_pass=$(generate_password)
echo "Generated Lavalink password: ${bold}$lavalink_pass${normal}"
echo

replace_line_in_file "lavalink/application.yml" "password:.*$" "password: $lavalink_pass" "Lavalink password"

# =============== Set up MOCBOT config ===============
echo
echo -e "${CYAN}Setting up MOCBOT${NC}"
echo ======================================================
copy_file_if_not_exist "bot" "config.template.yml" "config.yml"

mocbot_socket_key=$(generate_password)
echo "Generated MOCBOT websocket key: ${bold}$mocbot_socket_key${normal}"
echo

mocbot_socket_key_hash=$(calc_sha256 "$mocbot_socket_key")
replace_line_in_file "bot/config.yml" "KEY:.*$" "KEY: $mocbot_socket_key_hash" "MOCBOT websocket key hash"

replace_line_in_file "bot/config.yml" "API_KEY:.*$" "API_KEY: $mocbot_api_key" "MOCBOT API key"
replace_line_in_file "bot/config.yml" "PASS:.*$" "PASS: $lavalink_pass" "Lavalink password"


# =============== Manual setup ===============
echo
echo -e "${CYAN}Discord Authentication${NC}"
echo ======================================================
copy_file_if_not_exist "website" ".env.template" ".env"

printf 'See the \e]8;;https://discord.com/developers/applications\e\\Discord Developer Portal\e]8;;\e\\ to generate a developer application.\nMOCBOT utilises two tokens for a production and development environment.\n\n'

read -p "Paste your production client ID here: " bot_client_id
read -p "Paste your production client secret here: " bot_client_secret
read -p "Paste your generated production bot token here: " bot_token_prod

replace_line_in_file "bot/config.yml" "PRODUCTION:.*$" "PRODUCTION: \"$bot_token_prod\"" "MOCBOT token"
replace_line_in_file "website/.env" "DISCORD_CLIENT_ID.*$" "DISCORD_CLIENT_ID=$bot_client_id" "MOCBOT client ID"
replace_line_in_file "website/.env" "DISCORD_CLIENT_SECRET.*$" "DISCORD_CLIENT_SECRET=$bot_client_secret" "MOCBOT client secret"
replace_line_in_file "website/.env" "DISCORD_TOKEN.*$" "DISCORD_TOKEN=$bot_token_prod" "MOCBOT token"


echo "Paste your development bot token here. If you don't want to utilise a dev environment, paste your production token here instead"
echo 
read -p "Paste your generated development/production bot token here: " bot_token_dev
replace_line_in_file "bot/config.yml" "DEVELOPMENT:.*$" "DEVELOPMENT: \"$bot_token_dev\"" "MOCBOT dev token"

read -p "To gain access to specific developer features, please enter the Discord user IDs of the users that you wish to be labelled as developers, space separated. (E.g.: 123 234 345): " developer_ids
echo -n "Creating an SQL script to add developer user IDs into the database"

while IFS=' ' read -ra items; do
    for item in "${items[@]}"; do
        echo "INSERT INTO Developers VALUES ($item);" >> mysql/data/sql-db-add-info.sql
    done
done <<< "$developer_ids"
echo -e "... ${GREEN}done${NC}"

echo
echo -e "${CYAN}Spotify Authentication${NC}"
echo ======================================================

printf "See the \e]8;;https://developer.spotify.com/dashboard\e\\Spotify Developer Portal\e]8;;\e\\ to generate spotify developer application.\nMOCBOT utilises this for music playing capabilities.\n\n"

read -p "Paste Spotify Client ID: " spotify_client_id
replace_line_in_file "bot/config.yml" "CLIENT_ID:.*$" "CLIENT_ID: \"$spotify_client_id\"" "Spotify client ID"
replace_line_in_file "lavalink/application.yml" "clientId:.*$" "clientId: \"$spotify_client_id\"" "Spotify client ID"

read -p "Paste Spotify Client Secret: " spotify_client_secret
replace_line_in_file "bot/config.yml" "CLIENT_SECRET:.*$" "CLIENT_SECRET: \"$spotify_client_secret\"" "Spotify client secret"
replace_line_in_file "lavalink/application.yml" "clientSecret:.*$" "clientSecret: \"$spotify_client_secret\"" "Spotify client secret"


echo 
echo -e "${CYAN}Website Setup${NC}"
echo ======================================================

replace_line_in_file "website/.env" "NEXTAUTH_SECRET.*$" "NEXTAUTH_SECRET=$(openssl rand -base64 32)" "NextAuth secret"
replace_line_in_file "website/.env" "API_KEY.*$" "API_KEY=$mocbot_api_key" "MOCBOT API key"
replace_line_in_file "website/.env" "SOCKET_KEY.*$" "SOCKET_KEY=$mocbot_socket_key" "MOCBOT websocket key"

# Google Recaptcha
printf "See the \e]8;;https://www.google.com/recaptcha/admin/site/347945671\e\\Google Recaptcha Admin Console\e]8;;\e\\ to generate a recaptcha application.\nMOCBOT utilises this for user verification.\n\n"

read -p "Paste reCaptcha site key: " recaptcha_site_key
replace_line_in_file "website/.env" "NEXT_PUBLIC_RECAPTCHA_SITE_KEY.*$" "NEXT_PUBLIC_RECAPTCHA_SITE_KEY=$recaptcha_site_key" "reCaptcha site key"


read -p "Paste recaptcha secret key: " recaptcha_secret_key
replace_line_in_file "website/.env" "RECAPTCHA_SECRET_KEY.*$" "RECAPTCHA_SECRET_KEY=$recaptcha_secret_key" "reCaptcha secret key"

read -p "All done! Would you like to start the MOCBOT system? (y/n): " start_input
if [ $start_input == 'y' ]; then 
    docker compose up --build -d 
else 
    echo -e "You can start the MOCBOT service manually by running ${bold}docker compose up --build -d${normal}"
fi