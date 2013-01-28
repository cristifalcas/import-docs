#!/bin/bash

SCRIPT_PATH="$( cd "$( dirname "$0" )" && pwd )"
WIKI_DIR_PATH="/mnt/wiki_files/wiki_files"
mkdir -p "$WIKI_DIR_PATH"
LOG_PATH="/var/log/mind/wiki_logs/wiki_"
mkdir -p "/var/log/mind/wiki_logs/"
export LC_ALL=en_US.UTF-8
CMD="nice -n 20 perl"
CMD="perl"

case "$1" in
"update_ftp")
  PATTERN="ppt,PPT,PPt,PpT,pPT,Ppt,pPt,ppT,pptx,PPTx,PPtx,PpTx,pPTx,Pptx,pPtx,ppTx,pptX,PPTX,PPtX,PpTX,pPTX,PptX,pPtX,ppTX"
  OPTS="-N -r -l inf --no-remove-listing"
  OUTPUT_PATH="/mnt/wiki_files/wiki_files/ftp_mirror/"
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
"update_sp")
    $CMD "$SCRIPT_PATH"/update_service_packs.pl > "$LOG_PATH"update_service_packs &
  ;;
"update_svn")
    $CMD "$SCRIPT_PATH"/update_SVN.pl "$WIKI_DIR_PATH"/Documentation/svn/ > "$LOG_PATH"update_svn &
  ;;
"import_svn")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/svn/svn_mind_docs/ -n mind_svn > "$LOG_PATH"import_svn_mind
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/svn/svn_cms_docs/ -n cms_svn > "$LOG_PATH"import_svn_cms
  ;;
"update_sc")
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/b1 "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_until_7.0/	b1 > "$LOG_PATH"update_sc_until_7.0
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/b2 "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_after_7.0/	b2 > "$LOG_PATH"update_sc_after_7.0
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/cancel  "$WIKI_DIR_PATH"/Documentation/sc/sccanceled_docs/	cancel  > "$LOG_PATH"update_sc_cancel
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/i  "$WIKI_DIR_PATH"/Documentation/sc/scsentori_docs/	i  > "$LOG_PATH"update_sc_i
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/f  "$WIKI_DIR_PATH"/Documentation/sc/scsip_docs/		f  > "$LOG_PATH"update_sc_f 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/h  "$WIKI_DIR_PATH"/Documentation/sc/scinfrastructure_docs/ h > "$LOG_PATH"update_sc_h
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/r  "$WIKI_DIR_PATH"/Documentation/sc/scpmg_docs/		r  > "$LOG_PATH"update_sc_r 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/d  "$WIKI_DIR_PATH"/Documentation/sc/scphonexone_docs/	d  > "$LOG_PATH"update_sc_d 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/e  "$WIKI_DIR_PATH"/Documentation/sc/sccms_docs/		e  > "$LOG_PATH"update_sc_e 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/g  "$WIKI_DIR_PATH"/Documentation/sc/scmindreporter_docs/	g  > "$LOG_PATH"update_sc_g 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/s  "$WIKI_DIR_PATH"/Documentation/sc/scsimulators_docs/	s  > "$LOG_PATH"update_sc_s 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/t  "$WIKI_DIR_PATH"/Documentation/sc/scnagios_docs/	t  > "$LOG_PATH"update_sc_t 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/k  "$WIKI_DIR_PATH"/Documentation/sc/scabacus_docs/	k  > "$LOG_PATH"update_sc_k 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/z  "$WIKI_DIR_PATH"/Documentation/sc/scother_docs/	z  > "$LOG_PATH"update_sc_z 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/a  "$WIKI_DIR_PATH"/Documentation/sc/scphonex_docs/	a  > "$LOG_PATH"update_sc_a 
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/p  "$WIKI_DIR_PATH"/Documentation/sc/scplugins_docs/	p  > "$LOG_PATH"update_sc_p
  ;;
"import_sc")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_until_7.0/	-n sc_docs > "$LOG_PATH"import_sc_until_7.0
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_after_7.0/	-n sc_docs > "$LOG_PATH"import_sc_after_7.0
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsip_docs/	-n sc_docs > "$LOG_PATH"import_sc_f
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsentori_docs/	-n sc_docs > "$LOG_PATH"import_sc_i
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scinfrastructure_docs/ -n sc_docs > "$LOG_PATH"import_sc_h
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scpmg_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_r
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scphonexone_docs/ -n sc_docs > "$LOG_PATH"import_sc_d
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/sccms_docs/	-n sc_docs > "$LOG_PATH"import_sc_e
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmindreporter_docs/ -n sc_docs > "$LOG_PATH"import_sc_g
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsimulators_docs/ -n sc_docs  > "$LOG_PATH"import_sc_s
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scnagios_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_t
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scabacus_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_k
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scother_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_z
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scphonex_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_a
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scplugins_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_p
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/sccanceled_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_cancel
  ;;
"update_crm")
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$WIKI_DIR_PATH"/Documentation/crm/crm_iphonex/   m > "$LOG_PATH"update_crm_iphonex &
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$WIKI_DIR_PATH"/Documentation/crm/crm_phonexone/ p > "$LOG_PATH"update_crm_phonexone &
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$WIKI_DIR_PATH"/Documentation/crm/crm_sentori/   s > "$LOG_PATH"update_crm_sentori &
  ;;
"import_crm")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_iphonex/   -n crm_iphonex > "$LOG_PATH"import_crm_iphonex &
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_phonexone/ -n crm_phonexone > "$LOG_PATH"import_crm_phonexone &
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_sentori/   -n crm_sentori > "$LOG_PATH"import_crm_sentori &
  ;;
"import_users")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "/media/share/Documentation/Autoimport in wiki/" -n users >> "$LOG_PATH"import_users &
  ;;
"update_customers")
    $CMD "$SCRIPT_PATH"/update_customers.pl "$SCRIPT_PATH"/ > "$LOG_PATH"update_customers &
  ;;
"maintenance")
    $CMD "$SCRIPT_PATH"/maintenance.pl 0 > "$LOG_PATH"maintenance &
  ;;
"update_ppt")
    $CMD "$SCRIPT_PATH"/update_PPT.pl "$WIKI_DIR_PATH/ftp_mirror/" "$WIKI_DIR_PATH/ppt_as_flash/" u  > "$LOG_PATH"update_ppt &
  ;;
"import_ppt")
    $CMD "$SCRIPT_PATH"/update_PPT.pl "$WIKI_DIR_PATH/ftp_mirror/" "$WIKI_DIR_PATH/ppt_as_flash/" i  > "$LOG_PATH"import_ppt &
  ;;
"update_all")
    ##update_crm
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$WIKI_DIR_PATH"/Documentation/crm/crm_iphonex/   m > "$LOG_PATH"update_crm_iphonex &
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$WIKI_DIR_PATH"/Documentation/crm/crm_phonexone/ p > "$LOG_PATH"update_crm_phonexone &
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$WIKI_DIR_PATH"/Documentation/crm/crm_sentori/   s > "$LOG_PATH"update_crm_sentori &
    sleep 60

    ##update_ppt
    $CMD "$SCRIPT_PATH"/update_PPT.pl "$WIKI_DIR_PATH/ftp_mirror/" > "$LOG_PATH"update_ppt &
    sleep 120

    ##update_sc
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/b1 "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_5.3/	b1 > "$LOG_PATH"update_sc_5.3 &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/b2 "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_6.0/	b2 > "$LOG_PATH"update_sc_6.0 &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/b3 "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_6.5/	b3 > "$LOG_PATH"update_sc_6.5 &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/b4 "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_7.0/	b4 > "$LOG_PATH"update_sc_7.0 &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/b5 "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_10.0/	b5 > "$LOG_PATH"update_sc_10.0 &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/f  "$WIKI_DIR_PATH"/Documentation/sc/scsip_docs/		f  > "$LOG_PATH"update_sc_f &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/i  "$WIKI_DIR_PATH"/Documentation/sc/scsentori_docs/	i  > "$LOG_PATH"update_sc_i &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/h  "$WIKI_DIR_PATH"/Documentation/sc/scinfrastructure_docs/ h > "$LOG_PATH"update_sc_h &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/r  "$WIKI_DIR_PATH"/Documentation/sc/scpmg_docs/		r  > "$LOG_PATH"update_sc_r &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/d  "$WIKI_DIR_PATH"/Documentation/sc/scphonexone_docs/	d  > "$LOG_PATH"update_sc_d &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/e  "$WIKI_DIR_PATH"/Documentation/sc/sccms_docs/		e  > "$LOG_PATH"update_sc_e &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/g  "$WIKI_DIR_PATH"/Documentation/sc/scmindreporter_docs/	g  > "$LOG_PATH"update_sc_g &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/s  "$WIKI_DIR_PATH"/Documentation/sc/scsimulators_docs/	s  > "$LOG_PATH"update_sc_s &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/t  "$WIKI_DIR_PATH"/Documentation/sc/scnagios_docs/	t  > "$LOG_PATH"update_sc_t &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/k  "$WIKI_DIR_PATH"/Documentation/sc/scabacus_docs/	k  > "$LOG_PATH"update_sc_k &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/z  "$WIKI_DIR_PATH"/Documentation/sc/scother_docs/	z  > "$LOG_PATH"update_sc_z &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/a  "$WIKI_DIR_PATH"/Documentation/sc/scphonex_docs/	a  > "$LOG_PATH"update_sc_a &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/p  "$WIKI_DIR_PATH"/Documentation/sc/scplugins_docs/	p  > "$LOG_PATH"update_sc_p &
    $CMD "$SCRIPT_PATH"/update_SC.pl /tmp/wiki_update/cancel  "$WIKI_DIR_PATH"/Documentation/sc/sccanceled_docs/	cancel  > "$LOG_PATH"update_sc_cancel &

    ##update_svn
    $CMD "$SCRIPT_PATH"/update_SVN.pl "$WIKI_DIR_PATH"/Documentation/svn/ > "$LOG_PATH"update_svn &

    ##update_sp
    $CMD "$SCRIPT_PATH"/update_service_packs.pl  > "$LOG_PATH"update_service_packs &
  ;;
"import_all")
    ##update_customers
    $CMD "$SCRIPT_PATH"/update_customers.pl "$SCRIPT_PATH"/ > "$LOG_PATH"update_customers
    $CMD "$SCRIPT_PATH"/maintenance.pl 0 > "$LOG_PATH"maintenance
    ##import_crm
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_iphonex/   -n crm_iphonex > "$LOG_PATH"import_crm_iphonex &
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_phonexone/ -n crm_phonexone > "$LOG_PATH"import_crm_phonexone &
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/crm/crm_sentori/   -n crm_sentori > "$LOG_PATH"import_crm_sentori &

    ##import_svn
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/svn/svn_mind_docs/ -n mind_svn > "$LOG_PATH"import_svn_mind
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/svn/svn_cms_docs/ -n cms_svn > "$LOG_PATH"import_svn_cms

    ##import_sc
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_10.0/	-n sc_docs > "$LOG_PATH"import_sc_10.0
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_7.0/	-n sc_docs > "$LOG_PATH"import_sc_7.0
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/sccanceled_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_cancel
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_5.3/	-n sc_docs > "$LOG_PATH"import_sc_5.3
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_6.0/	-n sc_docs > "$LOG_PATH"import_sc_6.0
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmind_docs_6.5/	-n sc_docs > "$LOG_PATH"import_sc_6.5
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsip_docs/	-n sc_docs > "$LOG_PATH"import_sc_f
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsentori_docs/	-n sc_docs > "$LOG_PATH"import_sc_i
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scinfrastructure_docs/ -n sc_docs > "$LOG_PATH"import_sc_h
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scpmg_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_r
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scphonexone_docs/ -n sc_docs > "$LOG_PATH"import_sc_d
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/sccms_docs/	-n sc_docs > "$LOG_PATH"import_sc_e
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scmindreporter_docs/ -n sc_docs > "$LOG_PATH"import_sc_g
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scsimulators_docs/ -n sc_docs  > "$LOG_PATH"import_sc_s
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scnagios_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_t
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scabacus_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_k
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scother_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_z
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scphonex_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_a
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$WIKI_DIR_PATH"/Documentation/sc/scplugins_docs/ 	-n sc_docs > "$LOG_PATH"import_sc_p

    $CMD "$SCRIPT_PATH"/maintenance.pl 0 > "$LOG_PATH"maintenance
  ;;
*)
    echo "Incorrect parameter"
    exit 1
  ;;
esac
