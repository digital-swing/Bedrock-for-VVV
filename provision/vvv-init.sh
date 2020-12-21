#!/usr/bin/env bash
# Provision WordPress Stable

set -eo pipefail

echo " * Custom site template provisioner ${VVV_SITE_NAME} - downloads and installs a copy of WP stable for testing, building client sites, etc"

# fetch the first host as the primary domain. If none is available, generate a default using the site name
DB_NAME=$(get_config_value 'db_name' "${VVV_SITE_NAME}")
DB_NAME=${DB_NAME//[\\\/\.\<\>\:\"\'\|\?\!\*]/}
project=$DB_NAME
DB_PREFIX=$(get_config_value 'db_prefix' 'wp_')
DOMAIN=$(get_primary_host "${VVV_SITE_NAME}".test)
PUBLIC_DIR=$(get_config_value 'public_dir' "public_html")
SITE_TITLE=$(get_config_value 'site_title' "${DOMAIN}")
WP_LOCALE=$(get_config_value 'locale' 'fr_FR')
WP_TYPE=$(get_config_value 'wp_type' "single")
WP_VERSION=$(get_config_value 'wp_version' 'latest')

PUBLIC_DIR_PATH="${VVV_PATH_TO_SITE}"
if [ ! -z "${PUBLIC_DIR}" ]; then
  PUBLIC_DIR_PATH="${PUBLIC_DIR_PATH}/${PUBLIC_DIR}"
fi

# Make a database, if we don't already have one
setup_database() {
  echo -e " * Creating database '${DB_NAME}' (if it's not already there)"
  mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"
  echo -e " * Granting the wp user priviledges to the '${DB_NAME}' database"
  mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO wp@localhost IDENTIFIED BY 'wp';"
  echo -e " * DB operations done."
}

setup_nginx_folders() {
  echo " * Setting up the log subfolder for Nginx logs"
  noroot mkdir -p "${VVV_PATH_TO_SITE}/log"
  noroot touch "${VVV_PATH_TO_SITE}/log/nginx-error.log"
  noroot touch "${VVV_PATH_TO_SITE}/log/nginx-access.log"
}



generate_configs(){
  eval cd "${PUBLIC_DIR_PATH}"
  if [[ ! -f .env ]]
  then
    cp .env.example .env
    ls
    sed -i "s/DB_NAME='example'/DB_NAME='${DB_NAME}'/" .env
    sed -i "s/WP_HOME='http:\/\/example.test'/WP_HOME='http:\/\/${DB_NAME}.test'/" .env
    sed -i "s/DB_PREFIX='ds_wp_'/DB_PREFIX='${DB_PREFIX}'/" .env
  fi

  # Replace placeholders with actual project name
  for FILE in bedrock-ds.code-workspace grumphp.yml phpstan.neon .github/dependabot.yml jsconfig.json
  do
    if  [[ -f "$FILE" ]] ; then
      sed -i "s/bedrock-ds/$project/g" $FILE
    fi
  done
  
  if [[ -f "bedrock-ds.code-workspace" ]] && [[ ! -f "$project.code-workspace" ]]  ; then
    mv bedrock-ds.code-workspace "$project.code-workspace"
  fi
}

install_starter_theme(){
  eval cd "${PUBLIC_DIR_PATH}/web/app/themes"
  if [ -d "${project}-theme" ]
    then
      echo "Theme already installed"
    else
    # Start download theme
    echo "Downloading Starter Theme"
    git clone git@github.com:digital-swing/starter-theme.git "${project}-theme"
    eval cd "${project}-theme"
    # noroot composer install && yarn install
    echo "Starter Theme installed"
    # End download theme
  fi
}

copy_nginx_configs() {
  echo " * Copying the sites Nginx config template"
  if [ -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx-custom.conf" ]; then
    echo " * A vvv-nginx-custom.conf file was found"
    noroot cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx-custom.conf" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  else
    echo " * Using the default vvv-nginx-default.conf, to customize, create a vvv-nginx-custom.conf"
    noroot cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx-default.conf" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  fi
  echo " * Applying public dir setting to Nginx config"
  noroot sed -i "s#{vvv_public_dir}#/${PUBLIC_DIR}#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

  LIVE_URL=$(get_config_value 'live_url' '')
  if [ ! -z "$LIVE_URL" ]; then
    echo " * Adding support for Live URL redirects to NGINX of the website's media"
    # replace potential protocols, and remove trailing slashes
    LIVE_URL=$(echo "${LIVE_URL}" | sed 's|https://||' | sed 's|http://||'  | sed 's:/*$::')

    redirect_config=$((cat <<END_HEREDOC
if (!-e \$request_filename) {
  rewrite ^/[_0-9a-zA-Z-]+(/wp-content/uploads/.*) \$1;
}
if (!-e \$request_filename) {
  rewrite ^/wp-content/uploads/(.*)\$ \$scheme://${LIVE_URL}/wp-content/uploads/\$1 redirect;
}
END_HEREDOC
    ) |
    # pipe and escape new lines of the HEREDOC for usage in sed
    sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n\\1/g'
    )
    noroot sed -i -e "s|\(.*\){{LIVE_URL}}|\1${redirect_config}|" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  else
    noroot sed -i "s#{{LIVE_URL}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
  fi
}
restore_db_backup() {
  echo " * Found a database backup at ${1}. Restoring the site"
  noroot wp config set DB_USER "wp"
  noroot wp config set DB_PASSWORD "wp"
  noroot wp config set DB_HOST "localhost"
  noroot wp config set DB_NAME "${DB_NAME}"
  noroot wp config set table_prefix "${DB_PREFIX}"
  noroot wp db import "${1}"
  echo " * Installed database backup"
}

maybe_import_test_content() {
  INSTALL_TEST_CONTENT=$(get_config_value 'install_test_content' "")
  if [ ! -z "${INSTALL_TEST_CONTENT}" ]; then
    echo " * Downloading test content from github.com/poststatus/wptest/master/wptest.xml"
    noroot curl -s https://raw.githubusercontent.com/poststatus/wptest/master/wptest.xml > /tmp/import.xml
    echo " * Installing the wordpress-importer"
    noroot wp plugin install wordpress-importer
    echo " * Activating the wordpress-importer"
    noroot wp plugin activate wordpress-importer
    echo " * Importing test data"
    noroot wp import import.xml --authors=create
    echo " * Cleaning up import.xml"
    rm /tmp/import.xml
    echo " * Test content installed"
  fi
}

download_wp()
{
  # Download Bedrock
  echo "Installing Bedrock stack using Composer"

  cd "${VVV_PATH_TO_SITE}"
  if [ -d "${PUBLIC_DIR}" ] ; then
    echo "Public directory already installed"
  else
    git clone git@github.com:digital-swing/bedrock-ds.git "${PUBLIC_DIR}"
  fi
  echo "Bedrock stack installed using Composer"

}

install_packages(){
  cd ${PUBLIC_DIR_PATH}
  composer install
}

install_wp() {
  echo " * Installing WordPress"
  ADMIN_USER=$(get_config_value 'admin_user' "admin")
  ADMIN_PASSWORD=$(get_config_value 'admin_password' "password")
  ADMIN_EMAIL=$(get_config_value 'admin_email' "admin@local.test")
  echo " * Installing using wp core install --url=\"${DOMAIN}\" --title=\"${SITE_TITLE}\" --admin_name=\"${ADMIN_USER}\" --admin_email=\"${ADMIN_EMAIL}\" --admin_password=\"${ADMIN_PASSWORD}\""
  noroot wp core install --url="${DOMAIN}" --title="${SITE_TITLE}" --admin_name="${ADMIN_USER}" --admin_email="${ADMIN_EMAIL}" --admin_password="${ADMIN_PASSWORD}"
  echo " * WordPress was installed, with the username '${ADMIN_USER}', and the password '${ADMIN_PASSWORD}' at '${ADMIN_EMAIL}'"
  if [ "${WP_TYPE}" = "subdomain" ]; then
    echo " * Running Multisite install using wp core multisite-install --subdomains --url=\"${DOMAIN}\" --title=\"${SITE_TITLE}\" --admin_name=\"${ADMIN_USER}\" --admin_email=\"${ADMIN_EMAIL}\" --admin_password=\"${ADMIN_PASSWORD}\""
    noroot wp core multisite-install --subdomains --url="${DOMAIN}" --title="${SITE_TITLE}" --admin_name="${ADMIN_USER}" --admin_email="${ADMIN_EMAIL}" --admin_password="${ADMIN_PASSWORD}"
    echo " * Multisite install complete"
  elif [ "${WP_TYPE}" = "subdirectory" ]; then
    echo " * Running Multisite install using wp core ${INSTALL_COMMAND} --url=\"${DOMAIN}\" --title=\"${SITE_TITLE}\" --admin_name=\"${ADMIN_USER}\" --admin_email=\"${ADMIN_EMAIL}\" --admin_password=\"${ADMIN_PASSWORD}\""
    noroot wp core multisite-install --url="${DOMAIN}" --title="${SITE_TITLE}" --admin_name="${ADMIN_USER}" --admin_email="${ADMIN_EMAIL}" --admin_password="${ADMIN_PASSWORD}"
    echo " * Multisite install complete"
  fi
  DELETE_DEFAULT_PLUGINS=$(get_config_value 'delete_default_plugins' '')
  if [ -n "${DELETE_DEFAULT_PLUGINS}" ]; then
    echo " * Deleting the default plugins akismet and hello dolly"
    noroot wp plugin delete akismet
    noroot wp plugin delete hello
  fi

  wp package install aaemnnosttv/wp-cli-dotenv-command:^2.0
  wp dotenv salts generate
  wp post create --post_type=page --post_title='Styleguide' --post_status=publish
  maybe_import_test_content
}
update_wp() {
  cd ${PUBLIC_DIR_PATH}
  if [[ $(noroot composer show roots/wordpress | sed -n '/versions/s/^[^0-9]\+\([^,]\+\).*$/\1/p') > "${WP_VERSION}" ]]; then
    echo " * Installing an older version '${WP_VERSION}' of WordPress"
    noroot composer require roots/wordpress:${WP_VERSION}
  else
    echo " * Updating WordPress '${WP_VERSION}'"
    noroot composer require roots/wordpress
  fi
  cd ..
}

cd "${VVV_PATH_TO_SITE}"
setup_database
setup_nginx_folders

# Install and configure the latest stable version of WordPress
if [[ ! -f "${PUBLIC_DIR_PATH}/web/wp-config.php" ]]; then
  download_wp
fi
install_packages
generate_configs

# Install and configure the latest stable version of WordPress
if [[ ! -f "${PUBLIC_DIR_PATH}/web/wp/wp-load.php" ]]; then
  update_wp
fi

cd ${PUBLIC_DIR_PATH}
if ! $(noroot wp core is-installed ); then
  echo " * WordPress is present but isn't installed to the database, checking for SQL dumps in wp-content/database.sql or the main backup folder."
  if [ -f "${PUBLIC_DIR_PATH}/web/app/database.sql" ]; then
    restore_db_backup "${PUBLIC_DIR_PATH}/web/app/database.sql"
  elif [ -f "/srv/database/backups/${VVV_SITE_NAME}.sql" ]; then
    restore_db_backup "/srv/database/backups/${VVV_SITE_NAME}.sql"
  else
    install_wp
  fi
else
  update_wp
fi
copy_nginx_configs
install_starter_theme
echo " * Site Template provisioner script completed for ${VVV_SITE_NAME}"
