set ansi_nulls on
go
set quoted_identifier on
go

create procedure sch.build_queue
as
begin
	set nocount on
    ;

    -- clear out current queue
	truncate table sch.job_queue
	;

	-- create temporary calendar to determine dates with boolean workday
	declare
		@MinDate date = (select '1/1/2019'),
		@MaxDate date = getdate()
	;

	if object_id('tempdb..#calendar') is not null
		drop table #calendar
	select
		day,
		case
			when datepart(dw,day) in (1,7)
			or day in (select day from sch.holidays)
				then 'false' else 'true'
		end as workday
	into #calendar
	from (
		select top (datediff(day, @MinDate, @MaxDate) + 1)
			dateadd(day, row_number() over(order by a.object_id) - 1, @MinDate) as day
		from sys.all_objects a
			cross join sys.all_objects b
	) d
	;


	-- Monthlys

	-- create job_tree temp table to be manipulated by the evaluations
    create table #job_tree (
        jtid int,
        title nvarchar(255),
        sp_name nvarchar(255),
        active nvarchar(5),
        workdays nvarchar(5),
        days_of_month nvarchar(255),
        days_of_week nvarchar(255),
        hour nvarchar(255),
        minute nvarchar(255),
        if_non_wd nvarchar(5),
        class int,
        hierarchy int
    )
    ;

    -- populate tree data
    insert into #job_tree
    select * from sch.jobs where active = 'true'

	-- create temp table to list the jobs that will run today
	create table #todays_jobs (
		tjid int,
		rdate date
	)

	-- cursor to separate the commas and create a list of the jobs scheduled to run for the month and adj if non workday applies
	declare @branches int = (select count(*) from #job_tree where days_of_month like '%,%')
	while @branches > 0
	begin
		insert into #todays_jobs
		select
			jtid,
			case
				when if_non_wd = 'next'
					then (select min(day) from #calendar where workday = 'true' and day >= sch_dt)
				when if_non_wd = 'prev'
					then (select max(day) from #calendar where workday = 'true' and day <= sch_dt)
			end as adj_dt
		from (
			select
				jtid,
				cast( concat( datepart(yy,getdate()),'-',datepart(m,getdate()),'-',run_day) as date) sch_dt,
				days_of_month,
				if_non_wd
			from (
				select
					jtid,days_of_month,if_non_wd,
					case when run_day is null then days_of_month else run_day end as run_day
				from #job_tree
				left join (
					select days_of_month as dom,value as run_day from #job_tree
					cross apply string_split(
						(select top(1) days_of_month from #job_tree where days_of_month like '%,%'),','
					)
					where days_of_month like '%,%' and jtid = (
						select top(1) jtid from #job_tree where days_of_month like '%,%'
					)
				) dsom on dom = days_of_month
				where days_of_month <> 'all' and jtid not in (select tjid from #todays_jobs)
			) dom
		) monthlys

		delete #job_tree where jtid in (select tjid from #todays_jobs)
		set @branches = (select count(*) from #job_tree where days_of_month like '%,%')

	end
	;


	-- Weeklys

	-- refresh tree data
	truncate table #job_tree
	insert into #job_tree
	select * from sch.jobs where active = 'true'

	-- cursor to separate the commas and create a list of the jobs scheduled to run for the week and adj if non workday applies
	set @branches = (select count(*) from #job_tree where days_of_week like '%,%')
	while @branches > 0
	begin
		insert into #todays_jobs
		select
			jtid,
			case
				when wd = 'false' and if_non_wd = 'prev'
					then (select max(day) from #calendar where workday = 'true' and day <= sch_dt)
				when wd = 'false' and if_non_wd = 'next'
					then (select min(day) from #calendar where workday = 'true' and day >= sch_dt)
				else sch_dt
			end as adj_dt
		from (
			select
				jtid,dow,run_day,day as sch_dt,workday as wd,if_non_wd
			from (
				select
					jtid,days_of_week as dow,value as run_day,if_non_wd
				from #job_tree
				cross apply string_split(
					(select top(1) days_of_week from #job_tree where days_of_week like '%,%'),','
				)
				where days_of_week like '%,%' and jtid = (
						select top(1) jtid from #job_tree where days_of_week like '%,%'
					)
			) wkd
			left join #calendar on run_day = datepart(dw,day)
			where datepart(mm,day) = datepart(mm,getdate())
				and datepart(yy,day) = datepart(yy,getdate())
		) weeklys

		delete #job_tree where jtid in (select tjid from #todays_jobs)
		set @branches = (select count(*) from #job_tree where days_of_week like '%,%')

	end
	;


	-- Dailys | create a list of the jobs scheduled to run everyday and check against the workday binary
	insert into #todays_jobs
	select jid,today from (
		select
			jid,cast(getdate() as date) as today,workdays,
			(select workday from #calendar where day = cast(getdate() as date)) as is_wd
		from sch.jobs
		where active = 'true'
			and days_of_month = 'all'
			and days_of_week = 'all'
	) dailys
	where (workdays = 'true' and is_wd = 'true') or workdays = 'false'

	-- Keep only jobs from today
	delete from #todays_jobs where cast(getdate() as date) <> rdate


	-- Hours

	-- refresh tree data
	truncate table #job_tree
	insert into #job_tree
	select * from sch.jobs where jid in (select tjid from #todays_jobs)

	-- create temp table to store the run hours eval
	if object_id('tempdb..#run_hours') is not null
		drop table #run_hours
	create table #run_hours (rhid int,run_hr int)

	-- cursor to separate the commas and create a list of the hours scheduled to run for the active jobs
	set @branches = (select count(*) from #job_tree where hour like '%,%')
	while @branches > 0
	begin
		insert into #run_hours
		select * from
		(
			select
				jtid,value as run_hr
			from #job_tree
			cross apply string_split(
				(select top(1) hour from #job_tree where hour like '%,%'),','
			)
			where hour like '%,%' and jtid = (select top(1) jtid from #job_tree where hour like '%,%')

			union

			select
				jtid,hour as run_hr
			from #job_tree
			where hour not like '%,%'
		) hrs

		delete #job_tree where jtid in (select rhid from #run_hours)
		set @branches = (select count(*) from #job_tree where hour like '%,%')
	end
    ;


	-- Minutes

	-- create job_tree temp table to be manipulated by the hours evaluation
	--if object_id('tempdb..#job_tree') is not null
	truncate table #job_tree
	insert into #job_tree
	select * from sch.jobs where jid in (select tjid from #todays_jobs)

	-- create temp table to store the run minutes eval
	if object_id('tempdb..#run_mins') is not null
		drop table #run_mins
	create table #run_mins (rmid int,run_mn int)

	-- cursor to separate the commas and create a list of the minutes scheduled to run for the active jobs
	set @branches = (select count(*) from #job_tree where minute like '%,%')
	while @branches > 0
	begin
		insert into #run_mins
		select jtid,run_mn from
		(
			select
				jtid,value as run_mn
			from #job_tree
			cross apply string_split(
				(select top(1) minute from #job_tree where minute like '%,%'),','
			)
			where minute like '%,%' and jtid = (select top(1) jtid from #job_tree where minute like '%,%')

			union

			select
				jtid,minute as run_mn
			from #job_tree
			where minute not like '%,%'
		) mns

		delete #job_tree where jtid in (select rmid from #run_mins)
		set @branches = (select count(*) from #job_tree where minute like '%,%')
	end
    ;

	-- drop finished temp
	if object_id('tempdb..#job_tree') is not null
		drop table #job_tree

	-- join the day,hours,minutes tables back to the jobs table and insert the days schedule into the job_queue
	insert into sch.job_queue (
		jkey,title,sp_name,st_time,day
	)
	select rhid,title,sp_name,cast(concat(run_hr,':',run_mn) as time) as rtime,rdate
	from #run_hours
	left join #run_mins on rmid = rhid
	left join #todays_jobs on tjid = rhid
	left join sch.jobs on jid = rhid
	order by rdate,run_hr,run_mn
    ;


	-- drop finished temps
	if object_id('tempdb..#run_mins') is not null
		drop table #run_mins

	if object_id('tempdb..#run_hours') is not null
		drop table #run_hours

	if object_id('tempdb..#todays_jobs') is not null
		drop table #todays_jobs

end
go