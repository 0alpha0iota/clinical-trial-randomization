/**************************************************************************
* test1
* Simple randomization, N=30, allocation 1:1:1.
**************************************************************************/

options mprint mlogic symbolgen validvarname=v7;

%let repo_root=.;
%let test_root=./wxy_test/test1;

%include "&repo_root./macros/assertions.sas";
%include "&repo_root./macros/seed_utils.sas";
%include "&repo_root./macros/randomization_engine.sas";
%include "&repo_root./macros/reporting.sas";

%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=1,
    method=SIMPLE,
    sample_size=30,
    treatment_labels=%str(Low Dose|Middle Dose|High Dose),
    allocation=1:1:1,
    prefix=R,
    id_digits=3,
    id_shift=0,
    seed_mode=AUTO,
    overwrite=YES
);

%generate_randomization_rtf(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=1,
    title1=%str(Test1 Simple Randomization),
    title2=%str(Sample Size 30, Allocation 1:1:1),
    overwrite=YES
);

proc export data=rtcohrt.subject_rand_cohort1
    outfile="&test_root./test1_randomization_table.csv"
    dbms=csv
    replace;
run;

proc sql;
    create table work.test1_counts as
    select Treatment_Code, Treatment_Group, count(*) as N
    from rtcohrt.subject_rand_cohort1
    group by Treatment_Code, Treatment_Group
    order by Treatment_Code;
quit;

proc export data=work.test1_counts
    outfile="&test_root./test1_group_counts.csv"
    dbms=csv
    replace;
run;
