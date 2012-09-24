#!/bin/bash

OUT_DIR="/mnt/svn/"
mkdir -p "$OUT_DIR"
PREFIX="$OUT_DIR/$(date '+%d-%b-%Y')"

function bkp_scripts {
  echo "local scripts: vpn, expect"
  NAME=$PREFIX-scripts.tar.bz2
  tar cvjf $NAME /etc/sysconfig/iptables /etc/ppp/\
      /etc/cron.d/ /etc/vpnc/ /etc/openvpn/ /etc/ssmtp/ \
      /usr/local/vpn/ /usr/local/expect_scripts /usr/local/remote_expect/ \
      /home/vpnis/
}

function bkp_wikidir {
  echo "wiki files"
  NAME=$PREFIX-wiki-fs.tar.bz2
  tar cvjf $NAME \
      /mnt/wiki_files/wiki_files/html/wiki/
  NAME=$PREFIX-wiki-images.tar
  tar -cvf "$NAME" /var/www/html/wiki/images/[a-zA-Z0-9]
  #/var/www/html/wiki/images/*
}

# function bkp_wikihtml {
#   echo "wiki html"
#   NAME="$PREFIX-wiki-html.zip"
#   RES="/mnt/wiki_files/wiki_files/wiki_html"
#   php /var/www/html/wiki/maintenance/DumpHTML/dumpHTML.php \
#       -d $RES -k vector --image-snapshot --force-copy --no-overwrite
#   zip -r -qq "$NAME" "$RES"
# }

function bkp_fullxmldump {
  echo "wiki xml dump"
  NAME=$PREFIX-wiki-dump-xml.gz
  php /var/www/html/wiki/maintenance/dumpBackup.php --full | \
      /bin/gzip -9 > $NAME
}

function bkp_mysqldump {
  echo "mysql wikidb dump"
  NAME=$PREFIX-mysql-dump-sql.gz
  /usr/bin/mysqldump -u root -p\!0root@9 wikidb -c | /bin/gzip -9 > $NAME
}

function bkp_mysqldir {
  echo "mysql files"
  NAME=$PREFIX-mysql-fs.tar.bz2
  tar cvjf $NAME /var/lib/mysql/*
}

function bkp_fullos {
  echo "full OS"
  NAME=$PREFIX-linux.tgz
  tar -czvf "$NAME" \
      /bin/ /boot/ /etc/ /lib/ /opt/ /sbin/ /srv/ /usr/ /var/
}

function clean_wiki {
echo "clean wiki"
php /var/www/html/wiki/maintenance/deleteArchivedFiles.php --delete
php /var/www/html/wiki/maintenance/cleanupImages.php --fix

#Deletes all the archived (deleted from public) revisions, by clearing out the archive table.
#(should only delete from namespaces > 0)
php /var/www/html/wiki/maintenance/deleteArchivedRevisions.php --delete
#clean up unused texts, that are not linked to any existing or archived revision
php /var/www/html/wiki/maintenance/purgeOldText.php --purge
#delete revisions which refer to a nonexisting page
php /var/www/html/wiki/maintenance/deleteOrphanedRevisions.php

php /var/www/html/wiki/maintenance/namespaceDupes.php --fix
#echo "DELETE  from logging where log_timestamp < sysdate()-10000000000;" |mysql wikidb -u wikiuser -p\!0wikiuser\@9
}

function clean {
  echo "clean dirs"
  rm -rf /var/www/html/wiki/images/deleted/*
  rm -rf /home/vpnis/.java/deployment/log/
  rm -rf /mnt/share2/remote/auto_scripts/*
  find "$OUT_DIR/" -maxdepth 1 -type f -mtime +10 -exec rm {} \;
  find /mnt/share2/iptables_logs/ -mtime +30 -exec rm {} \;
  find /media/share/Documentation/cfalcas/q/import_docs/work/bad_dir/\
      -mtime +14 -exec rm {} \;
}

/bin/cp -f /etc/hosts.good /etc/hosts
bkp_scripts
bkp_wikidir
bkp_fullxmldump
bkp_mysqldir
bkp_mysqldump
bkp_fullos
clean
clean_wiki
#bkp_wikihtml
mysqlcheck -uwikiuser -p\!0wikiuser\@9 --databases wikidb --optimize
#php /var/www/html/wiki/maintenance/rebuildall.php
php /var/www/html/wiki/maintenance/refreshLinks.php


# rm `find /mnt/wiki_files/wiki_files/html/wiki/images/ -iname \*.jpg | grep "SVN:" | grep "_--_" | head -n 100 `
