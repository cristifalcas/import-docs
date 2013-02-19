#!/bin/bash

export_dir="/media/wiki_files/wiki_html_dump/"
threads=10
max=$(echo "SELECT MAX(page_id) FROM page" | mysql -u root wikidb -sN -p'!0root@9')
range=$(echo $max/$threads | bc)
start=1
end=$range

rm -rf "$export_dir"

for i in $(seq 1 $threads); do 
  php /var/www/html/wiki/extensions_mind/q/dumpHTML.php --munge-title windows -d $export_dir --image-snapshot --checkpoint /tmp/dumphtml_$i.checkpoint -s $start -e $end --show-titles > /tmp/dumpHTML_$i.log & 
  start=$end
  let end=$end+$range+100
done

find $export_dir -type f -iname \*.zip -exec rm -f {} \;
