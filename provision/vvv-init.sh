#!/bin/bash

project="${VVV_SITE_NAME}"
DB_NAME=${project//[\\\/\.\<\>\:\"\'\|\?\!\*]/}

DB_PREFIX=$(get_config_value 'db_prefix' 'ds_wp_')
DOMAIN=$(get_primary_host "${VVV_SITE_NAME}".test)
SITE_TITLE=$(get_config_value 'site_title' "${DOMAIN}")
WP_TYPE=$(get_config_value 'wp_type' "single")

ADMIN_USER=$(get_config_value 'admin_user' "DigitalSwing")
ADMIN_PASSWORD=$(get_config_value 'admin_password' "consolidou06")
ADMIN_EMAIL=$(get_config_value 'admin_email' "dev@digital-swing.com")

# Make a database, if we don't already have one
setup_database() {
  echo -e " * Creating database '${DB_NAME}' (if it's not already there)"
  mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"
  echo -e " * Granting the wp user priviledges to the '${DB_NAME}' database"
  mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO wp@localhost IDENTIFIED BY 'wp';"
  echo -e " * DB operations done."
}

maybe_import_test_content() {
  INSTALL_TEST_CONTENT=$(get_config_value 'install_test_content' "")
  if [  -n "${INSTALL_TEST_CONTENT}" ]; then
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


install_wp() {
  # Download Bedrock
  echo "Installing Bedrock stack using Composer"
  # TODO: change eval to cd ${VVV_PATH_TO_SITE}/public_html or use mkdir command
  eval cd .. && git clone git@github.com:digital-swing/bedrock-ds.git public_html
  echo "Bedrock stack installed using Composer"

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

generate_configs(){
  eval cd public_html
  if cmp --silent .env .env.example
  then
    rm -f .env
    git clone git@github.com:digital-swing/.env.git tempenv
    mv tempenv/.env .
    sed -i "s/DB_NAME='example'/DB_NAME='${DB_NAME}'/" .env
    sed -i "s/WP_HOME='http:\/\/example.test'/WP_HOME='http:\/\/${DB_NAME}.test'/" .env
    sed -i "s/DB_PREFIX='ds_wp_'/DB_PREFIX='${DB_PREFIX}'/" .env
  fi

  sed -i "s/{{ project }}/$project/g" example.code-workspace grumphp.yml phpstan.neon
  mv example.code-workspace "$project.code-workspace"

  rm -r tempenv
}

install_starter_theme(){
  eval cd public_html/web/app/themes
  if [ -d "$project-theme" ]
    then
      echo "Theme already installed"
    else
    # Start download theme
    echo "Downloading Starter Theme"
    git clone git@github.com:digital-swing/starter-theme.git "$project-theme"
    eval cd "$project-theme"
    noroot composer install && yarn install
    echo "Starter Theme installed"
    # End download theme
  fi
}



if [ ! -d public_html ]
then

  # Nginx Logs
  echo "Creating logs"
  mkdir -p "${VVV_PATH_TO_SITE}/log"
  touch "${VVV_PATH_TO_SITE}/log/error.log"
  touch "${VVV_PATH_TO_SITE}/log/access.log"

  setup_database
  install_wp
  install_starter_theme
  generate_configs

fi

# The Vagrant site setup script will restart Nginx for us

echo "$project Bedrock is now installed";

echo "Configuring Nginx";

cp -f "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf.tmpl" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"

if [ -n "$(type -t is_utility_installed)" ] && [ "$(type -t is_utility_installed)" = function ] && `is_utility_installed core tls-ca`; then
    sed -i "s#{{TLS_CERT}}#ssl_certificate /vagrant/certificates/${VVV_SITE_NAME}/dev.crt;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}#ssl_certificate_key /vagrant/certificates/${VVV_SITE_NAME}/dev.key;#" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
else
    sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
    sed -i "s#{{TLS_KEY}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
fi

sed -i "s#{{TLS_CERT}}##" "${VVV_PATH_TO_SITE}/provision/vvv-nginx.conf"
echo "Nginx configured!";
