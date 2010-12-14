#!/bin/bash

function batch_Import() {
    IN_PATH="./remote_batch_files/"
    DONE_PATH="$IN_PATH/done"
    mkdir "$DONE_PATH"
    find "$IN_PATH" -maxdepth 1 -type f -print0 | while read -d $'\0' file
    do
	FILE=$(basename "$file")
	php /var/www/html/wiki/maintenance/importTextFile.php "$file" --title "$FILE" && mv "$file" "$DONE_PATH"
    done
}

function copy_svn() {
    find ./Documentation/svn_docs/ -type f -print0 | egrep -i \*.xls$\|\*.doc$\|\*.docx$\|\*.rtf$\|svn_helper_trunk_info.txt$ -z | xargs -0 -I coco cp --parents "coco" -t ./test_docs/
}

function basckup_svn() {
    find ./Documentation/svn_docs/ -type f | egrep -i \*.xls$\|\*.doc$\|\*.docx$\|\*.rtf$\|svn_helper_trunk_info.txt$ > ./test_docs/files
    zip ./test_docs/zip.zip -@ < ./test_docs/files
}

function update_sc() {
    time ./update_SC.pl ./tmp/b1 ./Documentation/sc/scmind_docs_5.3/ b1 &
    time ./update_SC.pl ./tmp/b2 ./Documentation/sc/scmind_docs_6.0/ b2 &
    time ./update_SC.pl ./tmp/b3 ./Documentation/sc/scmind_docs_6.5/ b3 &
    time ./update_SC.pl ./tmp/b4 ./Documentation/sc/scmind_docs_7.0/ b4 &
    time ./update_SC.pl ./tmp/b5 ./Documentation/sc/scmind_docs_10.0/ b5&
}

update_sc
