#!/bin/bash
#rm -rf "/var/www/html/wiki/images/thumb/"
DIR="/mnt/wiki_files/wiki_files/work/"
chown wiki:wiki -R $DIR
DIR="/mnt/wiki_files/wiki_files/Documentation/"
chown wiki:wiki -R $DIR
DIR="/var/www/html/wiki/images/"
chown apache:apache -R $DIR
#find $DIR -type d -exec chmod 775 {} \;
#find $DIR -type f -exec chmod 664 {} \;
DIR="/media/share/Documentation/cfalcas/q/import_docs/"
chown wiki:nobody -R $DIR
#find $DIR -type d -exec chmod 775 {} \;
#find $DIR -type f -exec chmod 664 {} \;
exit 0

chcon -Rv --type=httpd_sys_content_t /var/www/html/wiki/
chcon -Rv --type=samba_share_t /media/share/Documentation/
