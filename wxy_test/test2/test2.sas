/**************************************************************************
* test2
* Block randomization, N=24, allocation 1:1, block length 4.
*
* In this framework, BLOCK allocation is exact counts in one block.
* Therefore block length 4 and 1:1 ratio are represented as allocation=2 2.
**************************************************************************/

options mprint mlogic symbolgen validvarname=v7;

%let repo_root=.;
%let test_root=./wxy_test/test2;

%include "&repo_root./macros/assertions.sas";
%include "&repo_root./macros/seed_utils.sas";
%include "&repo_root./macros/randomization_engine.sas";
%include "&repo_root./macros/reporting.sas";

%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=1,
    method=BLOCK,
    sample_size=24,
    treatment_labels=%str(Test Group|Control Group),
    allocation=2 2,
    prefix=R,
    id_digits=3,
    id_shift=0,
    seed_mode=AUTO,
    overwrite=YES
);

data work.test2_randomization_table;
    retain Rand_ID Block_No Treatment_Code Treatment_Group;
    set rtcohrt.subject_rand_cohort1;
    keep Rand_ID Block_No Treatment_Code Treatment_Group;
run;

proc export data=work.test2_randomization_table
    outfile="&test_root./test2_randomization_table.csv"
    dbms=csv
    replace;
run;

proc sql;
    create table work.test2_block_check as
    select Block_No,
           sum(Treatment_Code=1) as Test_Group_N,
           sum(Treatment_Code=2) as Control_Group_N,
           case
               when calculated Test_Group_N=2 and
                    calculated Control_Group_N=2
               then 'PASS'
               else 'FAIL'
           end as Block_Check length=4
    from rtcohrt.subject_rand_cohort1
    group by Block_No
    order by Block_No;
quit;

proc export data=work.test2_block_check
    outfile="&test_root./test2_block_check.csv"
    dbms=csv
    replace;
run;
