/**************************************************************************
* Program: test6.sas
*
* Purpose
* -------
* Industrial-main style driver for stratified block randomization testing.
* This program contains configuration and macro calls only. Reusable logic
* remains in the macros directory.
*
* Test scenario
* -------------
* Stratification factors:
* - Sex: Male, Female
* - Age_Group: Under65, Over65
*
* Expected strata: 4
* Sample size per stratum: 10
* Within each stratum: Test Group : Placebo = 4 : 1 per block
**************************************************************************/

options mprint mlogic symbolgen validvarname=v7;


/*=========================================================================
* 1. RESOLVE PROJECT ROOT AND TEST ROOT
*
* A caller may define ROOT before running this program. If ROOT is empty,
* the known project path for this local validation run is used.
*=========================================================================*/
%global root test_root;

%macro rt_resolve_test6_paths;
    %if %sysevalf(%superq(root)=, boolean) %then %do;
        %let root=D:\W1nn1e\Documents\innoclinic\Randomization\clinical-trial-randomization;
    %end;

    %let test_root=&root.\wxy_test\test6;
%mend rt_resolve_test6_paths;

%rt_resolve_test6_paths;
%put NOTE: [TEST6] Project root: &root.;
%put NOTE: [TEST6] Test root: &test_root.;


/*=========================================================================
* 2. INCLUDE FRAMEWORK MODULES
*=========================================================================*/
%include "&root.\macros\assertions.sas";
%include "&root.\macros\seed_utils.sas";
%include "&root.\macros\randomization_engine.sas";
%include "&root.\macros\stratification.sas";
%include "&root.\macros\reporting.sas";


/*=========================================================================
* 3. STUDY METADATA
*
* These values are available to customized titles and downstream reporting.
*=========================================================================*/
%let protocol_name    =Test6 Stratified Block Randomization;
%let protocol_number  =TEST6-STRAT-BLOCK;
%let sponsor          =Test Sponsor;
%let producer         =Innoclinic;
%let document_version =V1.0;


/*=========================================================================
* 4. EXECUTION SWITCHES
*=========================================================================*/
%let RUN_COHORT =YES;
%let RUN_REPORT =YES;
%let RUN_EXPORT =YES;


/*=========================================================================
* 5. STRATIFIED COHORT RANDOMIZATION CONFIGURATION
*
* Stratification is a wrapper around the within-stratum randomization
* method. In this test, each stratum independently uses BLOCK randomization.
*=========================================================================*/
%let table_type             =SUBJECT;
%let cohort_no              =1;
%let method                 =BLOCK;
%let stratification_factors =%str(Sex: Male, Female|Age_Group: Under65, Over65);
%let stratum_sample_sizes   =10 10 10 10;
%let treatment_labels       =%str(Test Group|Placebo);
%let allocation             =4 1;
%let prefix                 =R;
%let id_digits              =3;
%let id_shift               =0;
%let seed_mode              =AUTO;
%let fixed_seed             =;
%let overwrite              =YES;


/*=========================================================================
* 6. OPTIONAL RTF LISTING
*
* For stratified output, the report macro creates one page per stratum.
*=========================================================================*/
%let report_title1=&protocol_name;
%let report_title2=%str(Sex by Age Group);


/*=========================================================================
* 7. OPTIONAL VALIDATION EXPORTS
*=========================================================================*/
%macro rt_test6_export_checks;
    proc export data=rtcohrt.subject_rand_cohort&cohort_no
        outfile="&test_root.\test6_randomization_table.csv"
        dbms=csv
        replace;
    run;

    proc export data=rtcohrt.subject_seed_cohort&cohort_no
        outfile="&test_root.\test6_seed_audit.csv"
        dbms=csv
        replace;
    run;

    proc sql;
        create table work.test6_stratum_counts as
        select Stratum_No, Sex, Age_Group, Treatment_Code,
               Treatment_Group, count(*) as N
        from rtcohrt.subject_rand_cohort&cohort_no
        group by Stratum_No, Sex, Age_Group,
                 Treatment_Code, Treatment_Group
        order by Stratum_No, Treatment_Code;

        create table work.test6_block_check as
        select Stratum_No, Sex, Age_Group, Block_No,
               sum(Treatment_Code=1) as Test_Group_N,
               sum(Treatment_Code=2) as Placebo_N,
               case
                   when calculated Test_Group_N=4 and
                        calculated Placebo_N=1
                   then 'PASS'
                   else 'FAIL'
               end as Block_Check length=4
        from rtcohrt.subject_rand_cohort&cohort_no
        group by Stratum_No, Sex, Age_Group, Block_No
        order by Stratum_No, Block_No;

        create table work.test6_seed_audit_count as
        select count(*) as N, count(distinct Stratum_No) as Strata_N
        from rtcohrt.subject_seed_cohort&cohort_no;
    quit;

    proc export data=work.test6_stratum_counts
        outfile="&test_root.\test6_stratum_counts.csv"
        dbms=csv
        replace;
    run;

    proc export data=work.test6_block_check
        outfile="&test_root.\test6_block_check.csv"
        dbms=csv
        replace;
    run;

    proc export data=work.test6_seed_audit_count
        outfile="&test_root.\test6_seed_audit_count.csv"
        dbms=csv
        replace;
    run;
%mend rt_test6_export_checks;


/*=========================================================================
* 8. EXECUTE CONFIGURED STEPS
*=========================================================================*/
%macro rt_execute_test6_steps;
    %if %upcase(&RUN_COHORT)=YES %then %do;
        %generate_stratified_rand(
            root_path=&test_root,
            table_type=&table_type,
            cohort_no=&cohort_no,
            method=&method,
            stratification_factors=&stratification_factors,
            stratum_sample_sizes=&stratum_sample_sizes,
            treatment_labels=&treatment_labels,
            allocation=&allocation,
            prefix=&prefix,
            id_digits=&id_digits,
            id_shift=&id_shift,
            seed_mode=&seed_mode,
            fixed_seed=&fixed_seed,
            overwrite=&overwrite
        );
    %end;

    %if %upcase(&RUN_REPORT)=YES %then %do;
        %generate_randomization_rtf(
            root_path=&test_root,
            table_type=&table_type,
            cohort_no=&cohort_no,
            title1=&report_title1,
            title2=&report_title2,
            overwrite=&overwrite
        );
    %end;

    %if %upcase(&RUN_EXPORT)=YES %then %do;
        %rt_test6_export_checks;
    %end;
%mend rt_execute_test6_steps;

%rt_execute_test6_steps;
