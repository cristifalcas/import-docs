#!/bin/bash

SCRIPT_PATH="$( cd "$( dirname "$0" )" && pwd )"
LOG_PATH="/var/log/mind/wiki_"

case "$1" in
"update_svn")
    perl "$SCRIPT_PATH"/update_SVN.pl "$SCRIPT_PATH"/Documentation/svn/ &> "$LOG_PATH"update_svn &
  ;;
"import_svn")
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/svn/svn_mind_docs/ -n mind_svn &> "$LOG_PATH"import_svn_mind
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/svn/svn_cms_docs/ -n cms_docs &> "$LOG_PATH"import_svn_cms
  ;;
"update_sc")
    perl "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b1 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_5.3/	b1 &> "$LOG_PATH"update_sc_5.3 &
    perl "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b2 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_6.0/	b2 &> "$LOG_PATH"update_sc_6.0 &
    perl "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b3 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_6.5/	b3 &> "$LOG_PATH"update_sc_6.5 &
    perl "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b4 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_7.0/	b4 &> "$LOG_PATH"update_sc_7.0 &
    perl "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/b5 "$SCRIPT_PATH"/Documentation/sc/scmind_docs_10.0/	b5 &> "$LOG_PATH"update_sc_10.0 &
    perl "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/f  "$SCRIPT_PATH"/Documentation/sc/scsip_docs/		f  &> "$LOG_PATH"update_sc_f &
    perl "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/i  "$SCRIPT_PATH"/Documentation/sc/scsentori_docs/	i  &> "$LOG_PATH"update_sc_i &
    perl "$SCRIPT_PATH"/update_SC.pl "$SCRIPT_PATH"/tmp/h  "$SCRIPT_PATH"/Documentation/sc/infrastructure_docs/	h  &> "$LOG_PATH"update_sc_h &
  ;;
"import_sc")
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_5.3/	-n sc_docs &> "$LOG_PATH"import_sc_5.3
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_6.0/	-n sc_docs &> "$LOG_PATH"import_sc_6.0
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_6.5/	-n sc_docs &> "$LOG_PATH"import_sc_6.5
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_7.0/	-n sc_docs &> "$LOG_PATH"import_sc_7.0
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scmind_docs_10.0/	-n sc_docs &> "$LOG_PATH"import_sc_10.0
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scsip_docs/		-n sc_docs &> "$LOG_PATH"import_sc_f
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/scsentori_docs/	-n sc_docs &> "$LOG_PATH"import_sc_i
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/sc/infrastructure_docs/ -n sc_docs &> "$LOG_PATH"import_sc_h
  ;;
"import_crm")
    perl "$SCRIPT_PATH"/update_CRM.pl "$SCRIPT_PATH"/Documentation/crm_docs/ &> "$LOG_PATH"update_crm
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "$SCRIPT_PATH"/Documentation/crm_docs/ -n crm_docs &> "$LOG_PATH"import_crm
  ;;
"import_users")
    perl "$SCRIPT_PATH"/generate_wiki.pl -d "/media/share/Documentation/Autoimport in wiki/" -n users &> "$LOG_PATH"import_users &
  ;;
"update_customers")
    perl "$SCRIPT_PATH"/get_customers.pl "$SCRIPT_PATH"/ &> "$LOG_PATH"update_customers &
  ;;
*)
    echo "Incorrect parameter"
    exit 1
  ;;
esac
