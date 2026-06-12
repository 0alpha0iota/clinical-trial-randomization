/**************************************************************************
* test3
* Block randomization, N=22, allocation 1:1, block length 4.
*
* In this framework, BLOCK allocation is exact counts in one block.
* Therefore block length 4 and 1:1 ratio are represented as allocation=2 2.
* sample_size=22 is intentionally incompatible with block size 4.
**************************************************************************/

options mprint mlogic symbolgen validvarname=v7;

%let repo_root=.;
%let test_root=./wxy_test/test3;

%include "&repo_root./macros/assertions.sas";
%include "&repo_root./macros/seed_utils.sas";
%include "&repo_root./macros/randomization_engine.sas";
%include "&repo_root./macros/reporting.sas";

%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=1,
    method=BLOCK,
    sample_size=22,
    treatment_labels=%str(Test Group|Control Group),
    allocation=2 2,
    prefix=R,
    id_digits=3,
    id_shift=0,
    seed_mode=AUTO,
    overwrite=YES
);

%if %sysfunc(exist(rtcohrt.subject_rand_cohort1)) %then %do;
    proc export data=rtcohrt.subject_rand_cohort1
        outfile="&test_root./test3_randomization_table.csv"
        dbms=csv
        replace;
    run;
%end;
%else %do;
    data work.test3_result;
        length Result $200;
        Result='No randomization table was created because validation rejected the request.';
    run;

    proc export data=work.test3_result
        outfile="&test_root./test3_result.csv"
        dbms=csv
        replace;
    run;
%end;
