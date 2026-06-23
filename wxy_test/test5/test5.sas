/**************************************************************************
* test5
* First-pass stratified block randomization.
*
* Factors:
* - Sex: Male, Female
* - Age_Group: Under65, Over65
*
* Expected strata: 4
* Sample size per stratum: 10
* Within each stratum: Test Group : Placebo = 4 : 1 per block
**************************************************************************/

options mprint mlogic symbolgen validvarname=v7;

%let repo_root=D:\W1nn1e\Documents\innoclinic\Randomization\clinical-trial-randomization;
%let test_root=&repo_root.\wxy_test\test5;
%let overwrite=YES;

%include "&repo_root.\macros\assertions.sas";
%include "&repo_root.\macros\seed_utils.sas";
%include "&repo_root.\macros\stratification.sas";
%include "&repo_root.\macros\randomization_engine.sas";
%include "&repo_root.\macros\reporting.sas";

%generate_stratified_rand(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=1,
    method=BLOCK,
    stratification_factors=%str(Sex: Male, Female|Age_Group: Under65, Over65),
    stratum_sample_sizes=10 10 10 10,
    treatment_labels=%str(Test Group|Placebo),
    allocation=4 1,
    prefix=R,
    id_digits=3,
    id_shift=0,
    seed_mode=AUTO,
    overwrite=&overwrite
);

%generate_randomization_rtf(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=1,
    title1=%str(Test5 Stratified Block Randomization),
    title2=%str(Sex by Age Group),
    overwrite=&overwrite
);

proc export data=rtcohrt.subject_rand_cohort1
    outfile="&test_root.\test5_randomization_table.csv"
    dbms=csv
    replace;
run;

proc sql;
    create table work.test5_stratum_counts as
    select Stratum_No, Sex, Age_Group, Treatment_Code, Treatment_Group,
           count(*) as N
    from rtcohrt.subject_rand_cohort1
    group by Stratum_No, Sex, Age_Group, Treatment_Code, Treatment_Group
    order by Stratum_No, Treatment_Code;

    create table work.test5_block_check as
    select Stratum_No, Sex, Age_Group, Block_No,
           sum(Treatment_Code=1) as Test_Group_N,
           sum(Treatment_Code=2) as Placebo_N,
           case
               when calculated Test_Group_N=4 and calculated Placebo_N=1
               then 'PASS'
               else 'FAIL'
           end as Block_Check length=4
    from rtcohrt.subject_rand_cohort1
    group by Stratum_No, Sex, Age_Group, Block_No
    order by Stratum_No, Block_No;
quit;

proc export data=work.test5_stratum_counts
    outfile="&test_root.\test5_stratum_counts.csv"
    dbms=csv
    replace;
run;

proc export data=work.test5_block_check
    outfile="&test_root.\test5_block_check.csv"
    dbms=csv
    replace;
run;
