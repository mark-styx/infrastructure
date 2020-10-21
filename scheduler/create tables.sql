use dmp_dev_env
;


create schema sch
;

-- jobs table listing all jobs and the run schedule
create table sch.jobs (
    jid int identity primary key,
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


insert into sch.jobs
values
    ('test','test_sp0','true','true','all','all','6','30','next',null,null),
    ('test1','test_sp1','true','true','all','all','8,10','30','next',null,null),
    ('test2','test_sp2','true','true','all','all','8,10','30,45','next',null,null),
    ('test3','test_sp3','true','true','all','all','8','00,30','next',1,1),
    ('test4','test_sp4','true','true','all','2,4,6','6','30','prev',1,2),
    ('test5','test_sp5','true','true','15','all','6','30','next',null,null),
    ('test6','test_sp6','true','true','1,15','all','6','30','next',null,null),
    ('test7','test_sp7','true','true','25','all','6','30','prev',null,null),
    ('test8','test_sp8','true','true','all','2','6','30','next',null,null)
;

-- holiday table to be referenced by the temp workday calendar
create table sch.holidays (
    hid int identity primary key,
    holiday nvarchar(255),
    day date
)
;


insert into sch.holidays
values
    ('New Years Day','1/1/2020'),
    ('MLK Day','1/20/2020'),
    ('Presidents Day','2/17/2020'),
    ('Memorial Day','5/25/2020'),
    ('Independence Day','6/3/2020'),
    ('Labor Day','9/7/2020'),
    ('Election Day','11/3/2020'),
    ('Thanksgiving','11/26/2020'),
    ('Thanksgiving','11/27/2020'),
    ('Christmas','12/25/2020'),
    ('Christmas','12/28/2020'),
    ('Christmas','12/29/2020'),
    ('Christmas','12/30/2020'),
    ('Christmas','12/31/2020'),
    ('New Years Day','1/1/2021')
;

-- job pipeline for the days' jobs
create table sch.job_queue (
    qid int identity primary key,
    title nvarchar(255),
    sp_name nvarchar(255),
    st_time time,
    running nvarchar(5),
    day date,
    jkey int foreign key references sch.jobs
)
;

-- log completed jobs including status and outcome desc if failed
create table sch.job_log (
    lid int identity primary key,
    jkey int foreign key references sch.jobs,
    day date,
    st_time time,
    ed_time time,
    stat nvarchar(255),
    descr nvarchar(500)
)
;

-- create table to contain tests
create table sch.exec_testing (
    tid int identity primary key,
    title nvarchar(255),
    sp_name nvarchar(255),
    logged datetime
)
;

-- trigger to set default statuses on the jobs table
create trigger sch.job_defaults
on sch.jobs after insert
as
begin
    set nocount on;

    update sch.jobs
    set 
        active = case when active is null then 'true' else active end,
        workdays = case when workdays is null then 'true' else workdays end,
        days_of_month = case when days_of_month is null then 'all' else days_of_month end,
        days_of_week = case when days_of_week is null then 'all' else days_of_week end,
        if_non_wd = case when if_non_wd is null then 'next' else if_non_wd end
    ;
end