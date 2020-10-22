create function [sch].[calendar] (@stDate date,@edDate date)
returns table
as
return
(
    select
        day,
        case
            when datepart(dw,day) in (1,7)
            or day in (select day from sch.holidays)
                then 'false' else 'true'
        end as workday
    from (
        select top (datediff(day, @stDate, @edDate) + 1)
            dateadd(day, row_number() over(order by a.object_id) - 1, @stDate) as day
        from sys.all_objects a
            cross join sys.all_objects b
) d
);
go
