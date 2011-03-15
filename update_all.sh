#!/bin/bash

SCRIPT_PATH="$( cd "$( dirname "$0" )" && pwd )"
LOG_PATH="/var/log/mind/wiki_logs/wiki_"
export LC_ALL=en_US.UTF-8
CMD="nice -n 10 perl"

case "$1" in
"update_svn")
    $CMD "$SCRIPT_PATH"/update_SVN.pl "$SCRIPT_PATH"/Documentation/svn/ &> "$LOG_PATH"update_svn &
  ;;
"import_svn")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/svn/svn_mind_docs/ -n mind_svn &> "$LOG_PATH"import_svn_mind
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/svn/svn_cms_docs/ -n cms_svn &> "$LOG_PATH"import_svn_cms
  ;;
"update_sc")
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b1 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_5.3/	b1 &> "$LOG_PATH"update_sc_5.3 &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b2 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_6.0/	b2 &> "$LOG_PATH"update_sc_6.0 &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b3 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_6.5/	b3 &> "$LOG_PATH"update_sc_6.5 &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b4 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_7.0/	b4 &> "$LOG_PATH"update_sc_7.0 &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b5 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_10.0/	b5 &> "$LOG_PATH"update_sc_10.0 &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/f  "$SCRIPT_PATH"/Documentation/sc/scsip_docs/		f  &> "$LOG_PATH"update_sc_f &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/i  "$SCRIPT_PATH"/Documentation/sc/scsentori_docs/	i  &> "$LOG_PATH"update_sc_i &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/h  "$SCRIPT_PATH"/Documentation/sc/scinfrastructure_docs/	h  &> "$LOG_PATH"update_sc_h &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/r  "$SCRIPT_PATH"/Documentation/sc/scpmg_docs/	r  &> "$LOG_PATH"update_sc_r &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/d  "$SCRIPT_PATH"/Documentation/sc/scphonexone_docs/	d  &> "$LOG_PATH"update_sc_d &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/t  "$SCRIPT_PATH"/Documentation/sc/scnagios_docs/	t  &> "$LOG_PATH"update_sc_t &
    $CMD "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/cancel  "$SCRIPT_PATH"/Documentation/sc/sccanceled_docs/	cancel  &> "$LOG_PATH"update_sc_cancel &
  ;;
"import_sc")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_5.3/	-n sc_docs &> "$LOG_PATH"import_sc_5.3
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_6.0/	-n sc_docs &> "$LOG_PATH"import_sc_6.0
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_6.5/	-n sc_docs &> "$LOG_PATH"import_sc_6.5
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_7.0/	-n sc_docs &> "$LOG_PATH"import_sc_7.0
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_10.0/	-n sc_docs &> "$LOG_PATH"import_sc_10.0
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scsip_docs/		-n sc_docs &> "$LOG_PATH"import_sc_f
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scsentori_docs/	-n sc_docs &> "$LOG_PATH"import_sc_i
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scinfrastructure_docs/ -n sc_docs &> "$LOG_PATH"import_sc_h
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scpmg_docs/ 	-n sc_docs &> "$LOG_PATH"import_sc_r
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scphonexone_docs/ 	-n sc_docs &> "$LOG_PATH"import_sc_d
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scnagios_docs/ 	-n sc_docs &> "$LOG_PATH"import_sc_t
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/sccanceled_docs/ 	-n sc_docs &> "$LOG_PATH"import_sc_cancel
  ;;
"import_crm")
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$SCRIPT_PATH"/Documentation/crm/crm_iphonex/   m &> "$LOG_PATH"update_crm_iphonex
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$SCRIPT_PATH"/Documentation/crm/crm_phonexone/ p &> "$LOG_PATH"update_crm_phonexone
    $CMD "$SCRIPT_PATH"/update_CRM.pl "$SCRIPT_PATH"/Documentation/crm/crm_sentori/   s &> "$LOG_PATH"update_crm_sentori
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/crm/crm_iphonex/   -n crm_iphonex &> "$LOG_PATH"import_crm_iphonex
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/crm/crm_phonexone/ -n crm_phonexone &> "$LOG_PATH"import_crm_phonexone
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/crm/crm_sentori/   -n crm_sentori &> "$LOG_PATH"import_crm_sentori
  ;;
"import_users")
    $CMD "$SCRIPT_PATH"/generate_wiki.pl -d "/media/share/Documentation/Autoimport in wiki/" -n users &> "$LOG_PATH"import_users &
  ;;
"update_customers")
    $CMD "$SCRIPT_PATH"/update_customers.pl "$SCRIPT_PATH"/ &> "$LOG_PATH"update_customers &
  ;;
*)
    echo "Incorrect parameter"
    exit 1
  ;;
esac
