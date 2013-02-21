#!/bin/bash

threads=50
export_dir="/media/wiki_files/wiki_html_dump/"
max=$(echo "SELECT MAX(page_id) FROM page" | mysql -u root wikidb -sN -p'!0root@9')
range=$(echo $max/$threads | bc)
start=1
end=$range

sudo -u apache rm -rf "$export_dir"_prev
mv "$export_dir" "$export_dir"_prev

for i in $(seq 1 $threads); do 
  sudo -u apache php /var/www/html/wiki/extensions_mind/q/dumpHTML.php --munge-title windows -d $export_dir --image-snapshot --checkpoint /tmp/dumphtml_$i.checkpoint -s $start -e $end --show-titles > /tmp/dumpHTML_$i.log &
  start=$end
  let end=$end+$range+100
done
for job in `jobs -p`; do
    echo $job
    wait $job
done
sudo -u apache php /var/www/html/wiki/extensions_mind/q/dumpHTML.php -d $export_dir --categories --munge-title windows

sudo -u apache find $export_dir -type f -iname \*.zip -exec rm -f {} \;

#wget "http://kiwix.svn.sourceforge.net/viewvc/kiwix/dumping_tools/?view=tar" -O dumping_tools_master.tar
#perl -I /media/share/Documentation/cfalcas/q/import_docs/our_perl_lib/lib/ ./dumpHtml.pl --htmlPath=/media/wiki_files/wiki_html_dump_perl/ --mediawikiPath=/var/www/html/wiki/
#wget "https://gerrit.wikimedia.org/r/gitweb?p=openzim.git;a=snapshot;h=refs/heads/master;sf=tgz" -O zim_master.tgz
