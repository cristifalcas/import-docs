#!/bin/bash

SCRIPT_PATH="/media/share/Documentation/cfalcas/q/import_docs/"

time $SCRIPT_PATH/update_SC.pl ./tmp/b1 $SCRIPT_PATH/Documentation/sc/scmind_docs_5.3/	b1	&
time $SCRIPT_PATH/update_SC.pl ./tmp/b2 $SCRIPT_PATH/Documentation/sc/scmind_docs_6.0/	b2	&
time $SCRIPT_PATH/update_SC.pl ./tmp/b3 $SCRIPT_PATH/Documentation/sc/scmind_docs_6.5/	b3	&
time $SCRIPT_PATH/update_SC.pl ./tmp/b4 $SCRIPT_PATH/Documentation/sc/scmind_docs_7.0/  b4	&
time $SCRIPT_PATH/update_SC.pl ./tmp/b5 $SCRIPT_PATH/Documentation/sc/scmind_docs_10.0/	b5	&
time $SCRIPT_PATH/update_SC.pl ./tmp/f  $SCRIPT_PATH/Documentation/sc/scsip_docs/	f	&
time $SCRIPT_PATH/update_SC.pl ./tmp/i  $SCRIPT_PATH/Documentation/sc/scsentori_docs/	i	&
