#!/bin/sh

setup_wordpress(){
	test ! -d "$WORDPRESS_HOME" && echo "INFO: $WORDPRESS_HOME not found. creating ..." && mkdir -p "$WORDPRESS_HOME"

	cd $WORDPRESS_SOURCE
	tar -xf wp.tar.gz -C $WORDPRESS_HOME/ --strip-components=1
	
	chown -R www-data:www-data $WORDPRESS_HOME
    
}

load_wordpress(){
        if ! grep -q "^Include conf/httpd-wordpress.conf" $HTTPD_CONF_FILE; then
                echo 'Include conf/httpd-wordpress.conf' >> $HTTPD_CONF_FILE
        fi
}

test ! -d "$HTTPD_LOG_DIR" && echo "INFO: $HTTPD_LOG_DIR not found. creating..." && mkdir -p "$HTTPD_LOG_DIR"

echo "Setup openrc ..." && openrc && touch /run/openrc/softlevel

# That wp-config.php doesn't exist means WordPress is not installed/configured yet.
if [ ! -e "$WORDPRESS_HOME/wp-config.php" ]; then
	echo "INFO: $WORDPRESS_HOME/wp-config.php not found."
	echo "Installing WordPress for the first time ..." 
	setup_wordpress	

	echo "INFO: ++++++++++++++++++++++++++++++++++++++++++++++++++:"
	echo "INFO: WORDPRESS_ENVS:"
	echo "INFO: DATABASE_HOST:" $DB_HOST
	echo "INFO: WORDPRESS_DATABASE_NAME:" $DB_NAME
	echo "INFO: WORDPRESS_DATABASE_USERNAME:" $DB_USER
	echo "INFO: WORDPRESS_DATABASE_PASSWORD:" $DB_PASS	      
	echo "INFO: WORDPRESS_HOST:" $WP_FQDN  
	echo "INFO: ++++++++++++++++++++++++++++++++++++++++++++++++++:"

	cd $WORDPRESS_HOME 
	cp $WORDPRESS_SOURCE/wp-config.php . && chmod 777 wp-config.php && chown -R www-data:www-data wp-config.php
else
	echo "INFO: $WORDPRESS_HOME/wp-config.php already exists."
	echo "INFO: You can modify it manually as need."
fi	

echo "Loading WordPress conf ..."
load_wordpress
cd $WORDPRESS_HOME 
rm -rf $WORDPRESS_SOURCE

echo "Starting SSH ..."
rc-service sshd start

echo "Starting local Redis Server ..."
redis-server --daemonize yes

echo "Starting Apache httpd -D FOREGROUND ..."
apachectl start -D FOREGROUND