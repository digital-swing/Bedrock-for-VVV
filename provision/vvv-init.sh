project="${VVV_SITE_NAME}"

echo "Commencing Bedrock Setup"

# Make a database, if we don't already have one
echo "Creating database"
mysql -u root --password=root -e "CREATE DATABASE IF NOT EXISTS $project"
mysql -u root --password=root -e "GRANT ALL PRIVILEGES ON $project.* TO wp@localhost IDENTIFIED BY 'wp';"

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
  eval cd .. && composer create-project roots/bedrock public_html

  composer require wpackagist-plugin/safe-svg
  composer require wpackagist-plugin/better-wp-security
  composer require wpackagist-plugin/comet-cache
  composer require wpackagist-plugin/wp-sweep
  composer require wpackagist-plugin/ewww-image-optimizer
  composer require wpackagist-plugin/imsanity
  composer require wpackagist-plugin/host-analyticsjs-local
  composer require wpackagist-plugin/akismet
  composer require wpackagist-plugin/complianz-gdpr
  composer require wpackagist-plugin/query-monitor
  composer require wpackagist-plugin/regenerate-thumbnails
  composer require wpackagist-plugin/contact-form-7

  rm -f public_html/.env
  git clone git@github.com:digital-swing/.env.git public_html

  git clone git@github.com:digital-swing/movefile.git public_html

  # Start download theme
  echo "Downloading Theme"
  eval cd public_html/web/app/themes
  git clone git@github.com:digital-swing/sage.git $project-theme
  eval cd $project-theme
  composer install && npm install
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

echo "Nginx configured!";
