#!/bin/bash
rm -rf "/var/www/html/wiki/images/thumb"
DIR="/var/www/html/wiki/images/"
chown apache:wiki -R $DIR
find $DIR -type d -exec chmod 775 {} \;
find $DIR -type f -exec chmod 664 {} \;
DIR="/mnt/wiki_files/wiki_files/Documentation/"
chown wiki:nobody -R $DIR
DIR="/mnt/wiki_files/wiki_files/work/"
chown wiki:nobody -R $DIR

chcon -Rv --type=httpd_sys_content_t /var/www/html/wiki/
chcon -Rv --type=samba_share_t /media/share/Documentation/
