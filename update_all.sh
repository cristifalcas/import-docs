#!/bin/bash

SCRIPT_PATH="$( cd "$( dirname "$0" )" && pwd )"
WIKI_DIR_PATH="/media/wiki_files"
mkdir -p "$WIKI_DIR_PATH"
LOG_PATH="/var/log/mind/wiki_logs/wiki_"
mkdir -p "/var/log/mind/wiki_logs/"
export LC_ALL=en_US.UTF-8
# CMD="nice -n 20 perl"
CMD=perl

case "$1" in
"update_ftp")
  PATTERN="ppt,PPT,PPt,PpT,pPT,Ppt,pPt,ppT,pptx,PPTx,PPtx,PpTx,pPTx,Pptx,pPtx,ppTx,pptX,PPTX,PPtX,PpTX,pPTX,PptX,pPtX,ppTX"
  OPTS="-N -r -l inf --no-remove-listing"
  OUTPUT_PATH="/media/wiki_files/ftp_mirror/"
  wget $OPTS -P $OUTPUT_PATH ftp://10.10.1.10/SC/TestAttach -A.$PATTERN -o "$LOG_PATH"update_ftp_mirror_test.log &
  wget $OPTS -P $OUTPUT_PATH ftp://10.10.1.10/SC/MarketAttach -A.$PATTERN -o "$LOG_PATH"update_ftp_mirror_market.log &
  for i in {A..Z};do
    if [[ $i == "B" ]]; then
      for j in {0..9};do
	sleep 10
	wget $OPTS -P $OUTPUT_PATH ftp://10.10.1.10/SC/DefAttach/$i$j* -A.$PATTERN -o "$LOG_PATH"update_ftp_mirror_def_$i$j.log &
      done
    else
      sleep 10
      wget $OPTS -P $OUTPUT_PATH ftp://10.10.1.10/SC/DefAttach/$i* -A.$PATTERN -o "$LOG_PATH"update_ftp_mirror_def_$i.log &
    fi
  done
  ;;
"update_svn")
    $CMD "$SCRIPT_PATH"/update_SVN.pl "$WIKI_DIR_PATH"/Documentation/svn/ &
  ;;
"import_svn")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/svn/svn_mind_docs/ -n mind_svn
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/svn/svn_cms_docs/ -n cms_svn
  ;;
"update_sc")
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/b1 -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_until_7.0/ -n b1
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/b2 -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_after_7.0/ -n b2
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/cancel -d "$WIKI_DIR_PATH"/Documentation/sc/sccanceled_docs/ -n cancel
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/i  -d "$WIKI_DIR_PATH"/Documentation/sc/scsentori_docs/ -n i
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/f  -d "$WIKI_DIR_PATH"/Documentation/sc/scsip_docs/	-n f
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/h  -d "$WIKI_DIR_PATH"/Documentation/sc/scinfrastructure_docs/ -n h
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/r  -d "$WIKI_DIR_PATH"/Documentation/sc/scpmg_docs/	-n r
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/d  -d "$WIKI_DIR_PATH"/Documentation/sc/scphonexone_docs/ -n d
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/e  -d "$WIKI_DIR_PATH"/Documentation/sc/sccms_docs/	-n e
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/g  -d "$WIKI_DIR_PATH"/Documentation/sc/scmindreporter_docs/ -n g
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/s  -d "$WIKI_DIR_PATH"/Documentation/sc/scsimulators_docs/-n s
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/t  -d "$WIKI_DIR_PATH"/Documentation/sc/scnagios_docs/-n t
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/k  -d "$WIKI_DIR_PATH"/Documentation/sc/scabacus_docs/-n k
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/z  -d "$WIKI_DIR_PATH"/Documentation/sc/scother_docs/ -n z
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/a  -d "$WIKI_DIR_PATH"/Documentation/sc/scphonex_docs/ -n a
    $CMD "$SCRIPT_PATH"/update_SC.pl -t /tmp/wiki_update/p  -d "$WIKI_DIR_PATH"/Documentation/sc/scplugins_docs/ -n p
  ;;
"import_sc")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_until_7.0/	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_after_7.0/	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsip_docs/	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsentori_docs/	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scinfrastructure_docs/ -n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scpmg_docs/ 	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scphonexone_docs/ -n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/sccms_docs/	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmindreporter_docs/ -n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsimulators_docs/ -n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scnagios_docs/ 	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scabacus_docs/ 	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scother_docs/ 	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scphonex_docs/ 	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scplugins_docs/ 	-n sc_docs
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/sccanceled_docs/ 	-n sc_docs
  ;;
"update_crm")
    $CMD "$SCRIPT_PATH"/update_CRM.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_iphonex/   -n m &
    $CMD "$SCRIPT_PATH"/update_CRM.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_phonexone/ -n p &
    $CMD "$SCRIPT_PATH"/update_CRM.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_sentori/   -n s &
  ;;
"import_crm")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_iphonex/   -n crm_iphonex &
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_phonexone/ -n crm_phonexone &
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_sentori/   -n crm_sentori &
  ;;
"import_users")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "/media/share/Documentation/Autoimport in wiki/" -n users &
  ;;
"update_all")
    ##update_ppt
    $CMD "$SCRIPT_PATH"/update_PPT.pl "$WIKI_DIR_PATH/ftp_mirror/" "$WIKI_DIR_PATH/ppt_as_flash/" &
    sleep 120

    "$0" update_crm
    "$0" update_svn
    "$0" update_sc

    ##update_sp 
    $CMD "$SCRIPT_PATH"/update_service_packs.pl &
  ;;
"import_all")
    ##update_customers
    $CMD "$SCRIPT_PATH"/update_customers.pl "$SCRIPT_PATH"/ &
    $CMD "$SCRIPT_PATH"/maintenance.pl 0

    "$0" import_crm
    "$0" import_svn
    "$0" import_sc

    $CMD "$SCRIPT_PATH"/maintenance.pl 0
  ;;
*)
    echo "Incorrect parameter"
    exit 1
  ;;
esac
