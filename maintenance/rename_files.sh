#!/bin//bash

find ./ -name *.wiki -a ! -iname \*RN\:\* -type f -print0 | while read -d $'\0' file
    do
	FILE=$(basename "$file")
	DIR_FULL=$(dirname "$file")
	DIR=$(basename "$DIR_FULL")
	DIR_PATH=$(dirname "$DIR_FULL")
        #echo $DIR_PATH/$DIR/$FILE
	mkdir "$DIR_PATH/SVN:$DIR/"
        mv "$file" "$DIR_PATH/SVN:$DIR/SVN:$FILE"
        mv "$DIR_PATH/$DIR/"* "$DIR_PATH/SVN:$DIR/"
    done 
find -depth -type d -empty -exec rmdir {} \;
