--
-- COPY
--

-- directory paths are passed to us in environment variables
\getenv abs_srcdir PG_ABS_SRCDIR
\getenv abs_builddir PG_ABS_BUILDDIR

-- CLASS POPULATION
--	(any resemblance to real life is purely coincidental)
--
\set filename :abs_srcdir '/data/agg.data'
COPY aggtest FROM :'filename';

\set filename :abs_srcdir '/data/onek.data'
COPY onek FROM :'filename';

\set filename :abs_builddir '/results/onek.data'
COPY onek TO :'filename';

DELETE FROM onek;

COPY onek FROM :'filename';

\set filename :abs_srcdir '/data/tenk.data'
COPY tenk1 FROM :'filename';

\set filename :abs_srcdir '/data/rect.data'
COPY slow_emp4000 FROM :'filename';

\set filename :abs_srcdir '/data/person.data'
COPY person FROM :'filename';

\set filename :abs_srcdir '/data/emp.data'
COPY emp FROM :'filename';

\set filename :abs_srcdir '/data/student.data'
COPY student FROM :'filename';

\set filename :abs_srcdir '/data/stud_emp.data'
COPY stud_emp FROM :'filename';

\set filename :abs_srcdir '/data/streets.data'
COPY road FROM :'filename';

\set filename :abs_srcdir '/data/real_city.data'
COPY real_city FROM :'filename';

\set filename :abs_srcdir '/data/hash.data'
COPY hash_i4_heap FROM :'filename';

COPY hash_name_heap FROM :'filename';

COPY hash_txt_heap FROM :'filename';

COPY hash_f8_heap FROM :'filename';

\set filename :abs_srcdir '/data/tsearch.data'
COPY test_tsvector FROM :'filename';

\set filename :abs_srcdir '/data/jsonb.data'
COPY testjsonb FROM :'filename';

-- the data in this file has a lot of duplicates in the index key
-- fields, leading to long bucket chains and lots of table expansion.
-- this is therefore a stress test of the bucket overflow code (unlike
-- the data in hash.data, which has unique index keys).
--
-- \set filename :abs_srcdir '/data/hashovfl.data'
-- COPY hash_ovfl_heap FROM :'filename';

\set filename :abs_srcdir '/data/desc.data'
COPY bt_i4_heap FROM :'filename';

\set filename :abs_srcdir '/data/hash.data'
COPY bt_name_heap FROM :'filename';

\set filename :abs_srcdir '/data/desc.data'
COPY bt_txt_heap FROM :'filename';

\set filename :abs_srcdir '/data/hash.data'
COPY bt_f8_heap FROM :'filename';

\set filename :abs_srcdir '/data/array.data'
COPY array_op_test FROM :'filename';

\set filename :abs_srcdir '/data/array.data'
COPY array_index_op_test FROM :'filename';

-- analyze all the data we just loaded, to ensure plan consistency
-- in later tests

ANALYZE aggtest;
ANALYZE onek;
ANALYZE tenk1;
ANALYZE slow_emp4000;
ANALYZE person;
ANALYZE emp;
ANALYZE student;
ANALYZE stud_emp;
ANALYZE road;
ANALYZE real_city;
ANALYZE hash_i4_heap;
ANALYZE hash_name_heap;
ANALYZE hash_txt_heap;
ANALYZE hash_f8_heap;
ANALYZE test_tsvector;
ANALYZE bt_i4_heap;
ANALYZE bt_name_heap;
ANALYZE bt_txt_heap;
ANALYZE bt_f8_heap;
ANALYZE array_op_test;
ANALYZE array_index_op_test;

--- test copying in CSV mode with various styles
--- of embedded line ending characters

create temp table copytest (
	style	text,
	test 	text,
	filler	int);

insert into copytest values('DOS',E'abc\r\ndef',1);
insert into copytest values('Unix',E'abc\ndef',2);
insert into copytest values('Mac',E'abc\rdef',3);
insert into copytest values(E'esc\\ape',E'a\\r\\\r\\\n\\nb',4);

\set filename :abs_builddir '/results/copytest.csv'
copy copytest to :'filename' csv;

create temp table copytest2 (like copytest);

copy copytest2 from :'filename' csv;

select * from copytest except select * from copytest2;

truncate copytest2;

--- same test but with an escape char different from quote char

copy copytest to :'filename' csv quote '''' escape E'\\';

copy copytest2 from :'filename' csv quote '''' escape E'\\';

select * from copytest except select * from copytest2;


-- test header line feature

create temp table copytest3 (
	c1 int,
	"col with , comma" text,
	"col with "" quote"  int);

copy copytest3 from stdin csv header;
this is just a line full of junk that would error out if parsed
1,a,1
2,b,2
\.

copy copytest3 to stdout csv header;

-- test copy from with a partitioned table
create table parted_copytest (
	a int,
	b int,
	c text
) partition by list (b);

create table parted_copytest_a1 (c text, b int, a int);
create table parted_copytest_a2 (a int, c text, b int);

alter table parted_copytest attach partition parted_copytest_a1 for values in(1);
alter table parted_copytest attach partition parted_copytest_a2 for values in(2);

-- We must insert enough rows to trigger multi-inserts.  These are only
-- enabled adaptively when there are few enough partition changes.
insert into parted_copytest select x,1,'One' from generate_series(1,1000) x;
insert into parted_copytest select x,2,'Two' from generate_series(1001,1010) x;
insert into parted_copytest select x,1,'One' from generate_series(1011,1020) x;

\set filename :abs_builddir '/results/parted_copytest.csv'
copy (select * from parted_copytest order by a) to :'filename';

truncate parted_copytest;

copy parted_copytest from :'filename';

-- Ensure COPY FREEZE errors for partitioned tables.
begin;
truncate parted_copytest;
copy parted_copytest from :'filename' (freeze);
rollback;

select tableoid::regclass,count(*),sum(a) from parted_copytest
group by tableoid order by tableoid::regclass::name;

truncate parted_copytest;

-- create before insert row trigger on parted_copytest_a2
create function part_ins_func() returns trigger language plpgsql as $$
begin
  return new;
end;
$$;

create trigger part_ins_trig
	before insert on parted_copytest_a2
	for each row
	execute procedure part_ins_func();

copy parted_copytest from :'filename';

select tableoid::regclass,count(*),sum(a) from parted_copytest
group by tableoid order by tableoid::regclass::name;

truncate table parted_copytest;
create index on parted_copytest (b);
drop trigger part_ins_trig on parted_copytest_a2;

copy parted_copytest from stdin;
1	1	str1
2	2	str2
\.

-- Ensure index entries were properly added during the copy.
select * from parted_copytest where b = 1;
select * from parted_copytest where b = 2;

drop table parted_copytest;

--
-- Progress reporting for COPY
--
create table tab_progress_reporting (
	name text,
	age int4,
	location point,
	salary int4,
	manager name
);

-- Add a trigger to catch and print the contents of the catalog view
-- pg_stat_progress_copy during data insertion.  This allows to test
-- the validation of some progress reports for COPY FROM where the trigger
-- would fire.
create function notice_after_tab_progress_reporting() returns trigger AS
$$
declare report record;
begin
  -- The fields ignored here are the ones that may not remain
  -- consistent across multiple runs.  The sizes reported may differ
  -- across platforms, so just check if these are strictly positive.
  with progress_data as (
    select
       relid::regclass::text as relname,
       command,
       type,
       bytes_processed > 0 as has_bytes_processed,
       bytes_total > 0 as has_bytes_total,
       tuples_processed,
       tuples_excluded
      from pg_stat_progress_copy
      where pid = pg_backend_pid())
  select into report (to_jsonb(r)) as value
    from progress_data r;

  raise info 'progress: %', report.value::text;
  return new;
end;
$$ language plpgsql;

create trigger check_after_tab_progress_reporting
	after insert on tab_progress_reporting
	for each statement
	execute function notice_after_tab_progress_reporting();

-- Generate COPY FROM report with PIPE.
copy tab_progress_reporting from stdin;
sharon	25	(15,12)	1000	sam
sam	30	(10,5)	2000	bill
bill	20	(11,10)	1000	sharon
\.

-- Generate COPY FROM report with FILE, with some excluded tuples.
truncate tab_progress_reporting;
\set filename :abs_srcdir '/data/emp.data'
copy tab_progress_reporting from :'filename'
	where (salary < 2000);

drop trigger check_after_tab_progress_reporting on tab_progress_reporting;
drop function notice_after_tab_progress_reporting();
drop table tab_progress_reporting;
