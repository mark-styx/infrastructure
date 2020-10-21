set ansi_nulls on
go
set quoted_identifier on
go

create procedure sch.execute_job
as
begin
	set nocount on
    ;
	if object_id('tempdb..#batch') is not null
			drop table #batch
	select
		qid,jid,st_time,class,hierarchy
	into #batch
	from sch.job_queue
	left join sch.jobs on jkey = jid
	where st_time between cast(dateadd(minute,-15,getdate()) as time) and cast(getdate() as time)
	order by st_time,class,hierarchy
	;

	declare @query as nvarchar(max)
	declare @name as nvarchar(255)
	declare @sp_name as nvarchar(255)
	declare @st_time as datetime
	declare @ed_time as datetime
	declare @active as int
	declare @jobs as int
	declare @jid as int
	;

	set @jobs = (select count(*) from #batch)
	while @jobs > 0
	begin
		set @active = (select top(1) qid from #batch)
		set @sp_name = (select sp_name from sch.job_queue where qid = @active)
		set @name = (select title from sch.job_queue where qid = @active)
		set @jid = (select jkey from sch.job_queue where qid = @active)
		set @st_time = (select getdate())

		update sch.job_queue set running = 'True' where qid = @active
		set @query = 'insert into sch.exec_testing values ('''+@name+''','''+@sp_name+''','''+cast(@st_time as nvarchar(255))+''')'

		begin try
			exec sp_executesql @query
			set @ed_time = (select getdate())
			insert into sch.job_log
			values
				(@jid,cast(getdate() as date),@st_time,@ed_time,'success','job ran successfully')
		end try

		begin catch
			insert into sch.job_log
			values
				(@jid,cast(getdate() as date),@st_time,@ed_time,'failure',(select error_message()))
		end catch

		delete #batch where qid = @active
		delete from sch.job_queue where qid = @active
		set @jobs = (select count(*) from #batch)

	end
end
go