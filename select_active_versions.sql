set echo off;
SET FEEDBACK OFF;
SET HEADING OFF;
SET PAGESIZE 0;
SET COLSEP &1;
set pages 0 feed OFF;
set line 32767;
set TERMOUT OFF;
SET trimspool on;
set verify off;
WHENEVER SQLERROR EXIT SQL.SQLCODE;
WHENEVER OSERROR  EXIT -1;
spool &2; 
select vc_path
  from sc_versions_folders f
 where f.active = 'Y'
   and f.projectcode = 'B'
   and vc_path not like 'Customizations%'
   and vc_path not like 'Deployment%'
    order by 1;
spool off;
set markup HTML off;
exit 
