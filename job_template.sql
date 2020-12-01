--- Title
declare @proName as nvarchar(255)
set @proName = 'procedure_name'

exec mtn.procedure_run_log @proName

declare @section as nvarchar(255)
declare @err as nvarchar(max)


-- get data
set @section = 'get_data'
begin try
    exec mtn.procedure_section_logger @proName,@section
    select 'code goes here'
end try
begin catch
    set @err = (select concat(@section,' | ',error_message() ) )
    exec mtn.procedure_error_log @proName, @err
end catch


-- section 1
set @section = 'section1'
begin try
    exec mtn.procedure_section_logger @proName,@section
    select 'code goes here'
end try
begin catch
    set @err = (select concat(@section,' | ',error_message() ) )
    exec mtn.procedure_error_log @proName, @err
end catch


-- section 2
set @section = 'section2'
begin try
    exec mtn.procedure_section_logger @proName,@section
    select 'code goes here'
end try
begin catch
    set @err = (select concat(@section,' | ',error_message() ) )
    exec mtn.procedure_error_log @proName, @err
end catch


exec mtn.procedure_end_log @proName