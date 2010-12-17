#!/bin/bash

SCRIPT_PATH="/media/share/Documentation/cfalcas/q/import_docs/"

time perl $SCRIPT_PATH/update_SC.pl ./tmp/b1 $SCRIPT_PATH/Documentation/sc/scmind_docs_5.3/	b1 &>/var/log/mind/update_sc_5.3 &
time perl $SCRIPT_PATH/update_SC.pl ./tmp/b2 $SCRIPT_PATH/Documentation/sc/scmind_docs_6.0/	b2 &>/var/log/mind/update_sc_6.0 &
time perl $SCRIPT_PATH/update_SC.pl ./tmp/b3 $SCRIPT_PATH/Documentation/sc/scmind_docs_6.5/	b3 &>/var/log/mind/update_sc_6.5 &
time perl $SCRIPT_PATH/update_SC.pl ./tmp/b4 $SCRIPT_PATH/Documentation/sc/scmind_docs_7.0/	b4 &>/var/log/mind/update_sc_7.0 &
time perl $SCRIPT_PATH/update_SC.pl ./tmp/b5 $SCRIPT_PATH/Documentation/sc/scmind_docs_10.0/	b5 &>/var/log/mind/update_sc_10.0&
time perl $SCRIPT_PATH/update_SC.pl ./tmp/f  $SCRIPT_PATH/Documentation/sc/scsip_docs/		f  &>/var/log/mind/update_sc_f   &
time perl $SCRIPT_PATH/update_SC.pl ./tmp/i  $SCRIPT_PATH/Documentation/sc/scsentori_docs/	i  &>/var/log/mind/update_sc_i   &
