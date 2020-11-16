project="${VVV_SITE_NAME}"
DB_NAME=${project//[\\\/\.\<\>\:\"\'\|\?\!\*]/}
echo "Commencing Bedrock Setup"

# Make a database, if we don't already have one
echo -e " * Creating database '${DB_NAME}' (if it's not already there)"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\`"
echo -e " * Granting the wp user priviledges to the '${DB_NAME}' database"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO wp@localhost IDENTIFIED BY 'wp';"

# Download Bedrock
if [ ! -d public_html ]
then

  # Nginx Logs
  echo "Creating logs"
  mkdir -p ${VVV_PATH_TO_SITE}/log
  touch ${VVV_PATH_TO_SITE}/log/error.log
  touch ${VVV_PATH_TO_SITE}/log/access.log

  echo "Installing Bedrock stack using Composer"

  # TODO: change eval to cd ${VVV_PATH_TO_SITE}/public_html or use mkdir command
  eval cd .. && noroot composer create-project roots/bedrock public_html
  
  eval cd public_html


composer require wpackagist-plugin/acf-extended
  composer require wpackagist-plugin/akismet
  composer require wpackagist-plugin/amp
  composer require wpackagist-plugin/autoptimize
  composer require wpackagist-plugin/better-wp-security
  composer require wpackagist-plugin/comet-cache
  composer require wpackagist-plugin/complianz-gdpr
  composer require wpackagist-plugin/contact-form-7
  composer require wpackagist-plugin/ewww-image-optimizer
  composer require wpackagist-plugin/host-analyticsjs-local
  composer require wpackagist-plugin/imsanity
  composer require wpackagist-plugin/regenerate-thumbnails
  composer require wpackagist-plugin/safe-svg
  composer require wpackagist-plugin/wp-sweep
  composer require wpackagist-plugin/polylang
  composer require wpackagist-plugin/theme-translation-for-polylang
  composer require wpackagist-plugin/wp-php-console
  composer require wpackagist-plugin/show-current-template
  composer require wpackagist-plugin/theme-check
  composer require wpackagist-plugin/html-editor-syntax-highlighter
  composer require wpackagist-plugin/wp-nested-pages
  composer require wpackagist-plugin/stream
  composer require wpackagist-plugin/goodbye-captcha
  composer require wpackagist-plugin/nbsp-french
  composer require wp-security-audit-log

  composer require roots/soil

  composer config repositories.acf-pro '{"type": "vcs", "url": "https://pivvenit.github.io/acf-composer-bridge/composer/v3/wordpress-muplugin/"}'
  composer require advanced-custom-fields/advanced-custom-fields-pro

  composer config repositories.admin-columns-pro '{"type": "vcs", "url": "https://composer.admincolumns.com"}'
  composer require admin-columns/admin-columns-pro
  composer require admin-columns/ac-addon-acf

  composer config repositories.ds-lazy-load '{"type": "vcs", "url": "git@github.com:digital-swing/ds-lazy-load.git"}'
  composer require digital-swing/ds-lazy-load


  echo "{"\""bearer"\"": {"\""composer.admincolumns.com"\"": "\""cacc9610e8a4e69daa792372da987ddd"\""}}" > auth.json

  noroot composer config repositories.starter-theme-packages '{"type": "vcs", "url": "git@github.com:digital-swing/starter-theme-packages.git"}'
  noroot composer require digital-swing/starter-theme-packages:dev-main

  if cmp --silent .env .env.example
  then
    rm -f .env
    git clone git@github.com:digital-swing/.env.git tempenv
    mv tempenv/.env .
    sed -i "s/DB_NAME='example'/DB_NAME='${DB_NAME}'/" .env
    sed -i "s/WP_HOME='http:\/\/example.test'/WP_HOME='http:\/\/${DB_NAME}.test'/" .env
  fi

  git clone git@github.com:digital-swing/movefile.git tempmovefile
  mv tempmovefile/movefile.yml .

  rm -r tempenv tempmovefile
  eval cd ..

  # Start download theme
  echo "Downloading Theme"
  eval cd public_html/web/app/themes
  git clone git@github.com:digital-swing/sage.git $project-theme
  eval cd $project-theme
  noroot composer install && npm install
  # End download theme
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
