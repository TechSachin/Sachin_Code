SELECT db_name(er.database_id),

er.session_id,

es.original_login_name,

es.client_interface_name,

er.start_time,

er.status,

er.wait_type,

er.wait_resource,

SUBSTRING(st.text, (er.statement_start_offset/2)+1,

((CASE er.statement_end_offset

WHEN -1 THEN DATALENGTH(st.text)

ELSE er.statement_end_offset

END - er.statement_start_offset)/2) + 1) AS statement_text,

er.*

FROM SYS.dm_exec_requests er

join sys.dm_exec_sessions es on (er.session_id = es.session_id)

CROSS APPLY sys.dm_exec_sql_text(er.sql_handle) AS st

where er.session_id in

(SELECT distinct(blocking_session_id) FROM SYS.dm_exec_requests WHERE blocking_session_id > 0)

and blocking_session_id = 0