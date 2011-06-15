clones:

select a.changeid, a.parent_change_id, b.description
  from scchange a, sc_categories b
 where changetype = 'Change'
   and parent_change_id <> changeid
   and b.id = category_id
   and b.clone = 'Y'
   and changeid = 'B26982'



SPs:

select a.id,
       c.projectname,
       b.productname,
       a.version,
       a.service_pack,
       a.build_type,
       nvl(a.description, ' ') description,
       a.actual_build_date
  from SC_BUILD_MANAGER a, scprods b, SCPROJECTS c
 where actual_build_date > '1jan2010'
   and b.productid = a.product
   and a.projectcode = c.projectcode
 order by projectname, productname, version desc, service_pack desc


tasks in SP:

SELECT T1.CHANGEID,
       T1.CUSTOMER,
       T1.PRIORITY,
       T1.ChangeType,
       T1.STATUS,
       T1.TITLE,
       T1.COMMENTS,
       i.WorkerName InitiatorName
  FROM SCChange T1, SC_PLANS p, SC_BUILD_MANAGER b, SCWork i
 WHERE  T1.Product IS NOT NULL
   AND T1.ChangeId = p.CHANGE_ID
   AND b.ID(+) = p.BUILD_ID
   AND to_number(T1.Initiator) = i.ID(+)
   AND p.build_id = '76902'
 ORDER BY ChangeId

