--Query by CPU Usage
SELECT getdate() as "RunTime", st.text as batch,SUBSTRING(st.text,statement_start_offset / 2+1 , ( (CASE WHEN a.statement_end_offset = -1 THEN (LEN(CONVERT(nvarchar(max),st.text)) * 2) ELSE a.statement_end_offset END)  - a.statement_start_offset) / 2+1)  as current_statement
,qp.query_plan, a.* FROM sys.dm_exec_requests a CROSS APPLY sys.dm_exec_sql_text(a.sql_handle) as st CROSS APPLY sys.dm_exec_query_plan(a.plan_handle) as qp 
order by CPU_time desc

--DBCC FREEPROCCACHE(0x05000D0008E7E570206F65FD2902000001000000000000000000000000000000000000000000000000000000)
--SELECT * FROM sys.dm_exec_query_plan (0x05000D0057475369E05CA1216202000001000000000000000000000000000000000000000000000000000000)

--Blocking Chain
create table #ExecRequests (id BIGINT IDENTITY(1,1) PRIMARY KEY,session_id BIGINT not null,request_id BIGINT,start_time datetime,status nvarchar(4000),Command nvarchar(4000),sql_handle varbinary(4000)
,statement_start_offset BIGINT,statement_end_offset BIGINT,plan_handle varbinary (4000),database_id BIGINT,user_id BIGINT,blocking_session_id BIGINT,wait_type nvarchar (4000),wait_time BIGINT,CPU_Time BIGINT
,tot_time BIGINT,reads BIGINT,writes BIGINT,logical_reads BIGINT,[host_name] nvarchar(4000),[program_name] nvarchar(4000),blocking_these varchar(4000) null)
insert INTO #ExecRequests (session_id,request_id, start_time,status,Command,sql_handle,statement_start_offset,statement_end_offset,plan_handle,database_id,user_id,blocking_session_id,wait_type,wait_time,CPU_Time,tot_time,reads,writes,logical_reads,host_name, program_name)
select r.session_id,request_id, start_time,r.status,Command,sql_handle,statement_start_offset,statement_end_offset,plan_handle,r.database_id,user_id,blocking_session_id,wait_type,wait_time,r.CPU_Time,r.total_elapsed_time,r.reads,r.writes,r.logical_reads,s.host_name, s.program_name
from sys.dm_exec_requests r left outer join sys.dm_exec_sessions s on r.session_id = s.session_id where 1=1 
and r.session_id > 35 --retrieve only user spids 
and r.session_id <> @@SPID --ignore myself
update #ExecRequests set blocking_these = (select isnull(convert(varchar(5), er.session_id),'') + ', ' from #ExecRequests er where er.blocking_session_id = isnull(#ExecRequests.session_id ,0) and er.blocking_session_id <> 0 FOR XML PATH(''))
select r.session_id, r.host_name, r.program_name, r.status , r.blocking_these, 'LEN(Blocking)' = LEN(r.blocking_these), blocked_by = r.blocking_session_id, r.tot_time, DBName = db_name(r.database_id), r.Command, r.wait_type, r.tot_time, r.wait_time, r.CPU_Time, r.reads, r.writes, r.logical_reads, [text] = est.[text]
, offsettext = CASE WHEN r.statement_start_offset = 0 and r.statement_end_offset= 0 THEN null ELSE SUBSTRING (est.[text], r.statement_start_offset/2 + 1,CASE WHEN r.statement_end_offset = -1 THEN LEN (CONVERT(nvarchar(max), est.[text]))ELSE r.statement_end_offset/2 - r.statement_start_offset/2 + 1
END)END, r.statement_start_offset, r.statement_end_offset 
from #ExecRequests r outer apply sys.dm_exec_sql_text (r.sql_handle) est 
--where text like '%Primer_GetNewProducts_BySupplierName%' --where host_name like '%TXWeb%' --where db_name(r.database_id) = 'Mouser_COM' --where Command <> 'DB Mirror'
order by LEN(r.blocking_these) desc, blocked_by, r.session_id asc 
go
drop table #ExecRequests
--dbcc inputbuffer (199) --kill 199 WITH STATUSONLY
--kill 199

/*Monitor System Processes, check when a DBCC Shrink will finish*/
select Session_ID, Start_Time, Command, Percent_Complete, Estimated_Completion_Time, CPU_Time, Total_Elapsed_Time, Reads, Writes, CAST((estimated_completion_time/3600000) as varchar) + ' hour(s), ' + CAST((estimated_completion_time %3600000)/60000 as varchar) + 'min, '+ CAST((estimated_completion_time %60000)/1000 as varchar) + ' sec' as est_time_to_go
from sys.dm_exec_requests  --where command = 'DbccFilesCompact'
order by 5 desc

/*When will my backup/restore be done how long will it take*/
select session_id, convert(nvarchar(22),db_name(database_id)) as [database],
case command when 'BACKUP DATABASE' then 'DB' when 'RESTORE DATABASE' then 'DB RESTORE' when 'RESTORE VERIFYON' then 'VERIFYING' when 'RESTORE HEADERON' then 'VERIFYING HEADER' when 'RESTORE HEADERONLY' then 'VERIFYING HEADER' else 'LOG' end as [type],
start_time as [started],dateadd(mi,estimated_completion_time/60000,getdate()) as [finishing], datediff(mi, start_time, (dateadd(mi,estimated_completion_time/60000,getdate()))) - wait_time/60000 as [mins left], datediff(mi, start_time, (dateadd(mi,estimated_completion_time/60000,getdate()))) as [total wait mins (est)], convert(varchar(5),cast((percent_complete) as decimal (4,1))) as [% complete],
getdate() as [current time] from sys.dm_exec_requests where command in ('BACKUP DATABASE','BACKUP LOG','RESTORE DATABASE','RESTORE VERIFYON','RESTORE HEADERON','RESTORE HEADERONLY')


/*SP Runtime and Plan*/
SELECT CASE WHEN database_id = 32767 then 'Resource' ELSE DB_NAME(database_id)END AS DBName, qp.Query_Plan
      ,OBJECT_SCHEMA_NAME(object_id,database_id) AS [SCHEMA_NAME] 
      ,OBJECT_NAME(object_id,database_id)AS [OBJECT_NAME] 
      ,cp.*  FROM sys.dm_exec_procedure_stats  cp CROSS APPLY sys.dm_exec_query_plan(cp.plan_handle) AS qp
         where OBJECT_NAME(object_id,database_id) like '%me_GetFABDocumentValue%'
--DBCC FREEPROCCACHE(0x05001200423DF750D0E539B40700000001000000000000000000000000000000000000000000000000000000)
