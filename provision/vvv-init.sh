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
  eval cd .. && composer create-project roots/bedrock public_html
  
  eval cd public_html

  echo "{"\""bearer"\"": {"\""composer.admincolumns.com"\"": "\""cacc9610e8a4e69daa792372da987ddd"\""}}" > auth.json

  noroot composer config repositories.starter-theme-packages '{"composer": "vcs", "url": "git@github.com:digital-swing/starter-theme-packages.git"}'
  noroot composer require digital-swing/starter-theme-packages

  if cmp --silent .env .env.example
  then
    rm -f .env
    git clone git@github.com:digital-swing/.env.git tempenv
    mv tempenv/.env .
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
