/**************************************************************************
* test4
* Block randomization across three independent dose cohorts.
*
* Requirements:
* - Method: BLOCK
* - Cohorts: 3
* - Cohort 1: Low dose
* - Cohort 2: Middle dose
* - Cohort 3: High dose
* - Within each cohort: Test Group : Placebo = 4 : 1
* - Sample size per cohort: 10
* - Total sample size: 30
*
* In this framework, BLOCK allocation is expressed as exact counts in one
* block. Therefore allocation=4 1 means block size 5.
**************************************************************************/

options mprint mlogic symbolgen validvarname=v7;

%let repo_root=D:\W1nn1e\Documents\innoclinic\Randomization\clinical-trial-randomization;
%let test_root=D:\W1nn1e\Documents\innoclinic\Randomization\clinical-trial-randomization\wxy_test\test4;
%let overwrite=YES;

%include "&repo_root./macros/assertions.sas";
%include "&repo_root./macros/seed_utils.sas";
%include "&repo_root./macros/randomization_engine.sas";
%include "&repo_root./macros/reporting_new.sas";

%macro run_test4_cohort(cohort_no=, cohort_name=, id_shift=);
    %generate_cohort_randomization(
        root_path=&test_root,
        table_type=SUBJECT,
        cohort_no=&cohort_no,
        method=BLOCK,
        sample_size=10,
        treatment_labels=%str(Test Group|Placebo),
        allocation=4 1,
        prefix=R,
        id_digits=3,
        id_shift=&id_shift,
        seed_mode=AUTO,
        overwrite=&overwrite
    );

    %generate_randomization_rtf(
        root_path=&test_root,
        table_type=SUBJECT,
        cohort_no=&cohort_no,
        title1=%str(Test4 Block Randomization),
        title2=%str(&cohort_name),
        overwrite=&overwrite
    );

    data work.test4_cohort&cohort_no;
        length Cohort_Name $40;
        set rtcohrt.subject_rand_cohort&cohort_no;
        Cohort_Name="&cohort_name";
    run;
%mend run_test4_cohort;

%run_test4_cohort(cohort_no=1, cohort_name=Low Dose Cohort, id_shift=100);
%run_test4_cohort(cohort_no=2, cohort_name=Middle Dose Cohort, id_shift=200);
%run_test4_cohort(cohort_no=3, cohort_name=High Dose Cohort, id_shift=300);

data work.test4_randomization_table;
    set work.test4_cohort1 work.test4_cohort2 work.test4_cohort3;
run;

proc export data=work.test4_randomization_table
    outfile="&test_root./test4_randomization_table.csv"
    dbms=csv
    replace;
run;

proc sql;
    create table work.test4_group_counts as
    select Cohort_No, Cohort_Name, Treatment_Code, Treatment_Group, count(*) as N
    from work.test4_randomization_table
    group by Cohort_No, Cohort_Name, Treatment_Code, Treatment_Group
    order by Cohort_No, Treatment_Code;

    create table work.test4_block_check as
    select Cohort_No, Cohort_Name, Block_No,
           sum(Treatment_Code=1) as Test_Group_N,
           sum(Treatment_Code=2) as Placebo_N,
           case
               when calculated Test_Group_N=4 and calculated Placebo_N=1
               then 'PASS'
               else 'FAIL'
           end as Block_Check length=4
    from work.test4_randomization_table
    group by Cohort_No, Cohort_Name, Block_No
    order by Cohort_No, Block_No;
quit;

proc export data=work.test4_group_counts
    outfile="&test_root./test4_group_counts.csv"
    dbms=csv
    replace;
run;

proc export data=work.test4_block_check
    outfile="&test_root./test4_block_check.csv"
    dbms=csv
    replace;
run;
