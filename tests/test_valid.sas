/**************************************************************************
* Valid-path integration tests for the industrial randomization framework.
**************************************************************************/

options nomprint nomlogic nosymbolgen;

%global project_root test_root RT_TEST_FAILURES;
%let RT_TEST_FAILURES=0;

data _null_;
    length _sysin _root $2048;
    _sysin=dequote(strip(getoption('sysin')));
    _root=prxchange('s#[/\\]tests[/\\][^/\\]+$##', 1, _sysin);
    call symputx('project_root', _root, 'g');
    call symputx('test_root', cats(_root, '/tests'), 'g');
run;

%include "&project_root./macros/assertions.sas";
%include "&project_root./macros/seed_utils.sas";
%include "&project_root./macros/randomization_engine.sas";
%include "&project_root./macros/stratification.sas";
%include "&project_root./macros/reporting.sas";


%macro test_assert(condition=, message=);
    %if not (&condition) %then %do;
        %put ERROR: [TEST_FAILURE] &message;
        %let RT_TEST_FAILURES=%eval(&RT_TEST_FAILURES+1);
    %end;
    %else %put NOTE: [TEST_PASS] &message;
%mend test_assert;


/* Initialize the test output library and remove prior test artifacts. */
%rt_init_paths(root_path=&test_root);
proc datasets lib=rtcohrt nolist nowarn;
    delete
        stratification_code
        subject_rand_cohort101 subject_seed_cohort101
        drug_rand_cohort102 drug_seed_cohort102
        subject_rand_cohort103 subject_seed_cohort103;
quit;


/*-----------------------------------------------------------------------
* Test 1: Cartesian-product stratification codebook
*-----------------------------------------------------------------------*/
%generate_stratification_code(
    root_path=&test_root,
    stratification_factors=%str(
        Age: >=60, <60|
        Gender: F, M|
        Disease Type: A, B, C
    ),
    overwrite=YES
);

%test_assert(
    condition=%sysfunc(exist(rtcohrt.stratification_code)),
    message=Stratification codebook dataset exists
);

proc sql noprint;
    select count(*) into :_strata_rows trimmed
    from rtcohrt.stratification_code;

    select
        case
            when Age='>=60' and Gender='F' and
                 Disease_Type='A' and Stratum_No=1
            then 1 else 0
        end
    into :_first_stratum_ok trimmed
    from rtcohrt.stratification_code
    where Stratum_No=1;

    select
        case
            when Age='<60' and Gender='M' and
                 Disease_Type='C' and Stratum_No=12
            then 1 else 0
        end
    into :_last_stratum_ok trimmed
    from rtcohrt.stratification_code
    where Stratum_No=12;
quit;

%test_assert(condition=&_strata_rows=12,
             message=Stratification codebook has 12 rows);
%test_assert(condition=&_first_stratum_ok=1,
             message=First stratum follows deterministic factor ordering);
%test_assert(condition=&_last_stratum_ok=1,
             message=Last stratum follows deterministic factor ordering);


/*-----------------------------------------------------------------------
* Test 2: SIMPLE exact allocation and FIXED reproducibility
*-----------------------------------------------------------------------*/
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=101,
    method=SIMPLE,
    sample_size=40,
    treatment_labels=%str(Placebo|Active),
    allocation=1:3,
    prefix=ABC,
    id_digits=5,
    id_shift=100,
    seed_mode=FIXED,
    fixed_seed=246810,
    overwrite=YES
);

%test_assert(
    condition=%sysfunc(exist(rtcohrt.subject_rand_cohort101)),
    message=SIMPLE cohort dataset exists
);
%test_assert(
    condition=not %sysfunc(exist(rtcohrt.subject_seed_cohort101)),
    message=FIXED mode creates no seed audit dataset
);

proc sql noprint;
    select count(*), count(distinct Rand_ID),
           min(Rand_ID), max(Rand_ID),
           sum(not missing(Block_No)),
           sum(not missing(Position_In_Block))
    into :_simple_rows trimmed,
         :_simple_unique_ids trimmed,
         :_simple_min_id trimmed,
         :_simple_max_id trimmed,
         :_simple_block_values trimmed,
         :_simple_position_values trimmed
    from rtcohrt.subject_rand_cohort101;

    select count(*) into :_placebo_count trimmed
    from rtcohrt.subject_rand_cohort101
    where Treatment_Group='Placebo';

    select count(*) into :_active_count trimmed
    from rtcohrt.subject_rand_cohort101
    where Treatment_Group='Active';
quit;

%test_assert(condition=&_simple_rows=40 and &_simple_unique_ids=40,
             message=SIMPLE cohort has 40 unique IDs);
%test_assert(
    condition=%superq(_simple_min_id)=ABC00101 and
              %superq(_simple_max_id)=ABC00140,
    message=Prefix digits and ID shift are applied correctly
);
%test_assert(condition=&_placebo_count=10 and &_active_count=30,
             message=SIMPLE ratio 1:3 produces exact totals);
%test_assert(
    condition=&_simple_block_values=0 and &_simple_position_values=0,
    message=SIMPLE cohort has no block-specific values
);

data work._simple_first_run;
    set rtcohrt.subject_rand_cohort101;
run;

%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=101,
    method=SIMPLE,
    sample_size=40,
    treatment_labels=%str(Placebo|Active),
    allocation=1:3,
    prefix=ABC,
    id_digits=5,
    id_shift=100,
    seed_mode=FIXED,
    fixed_seed=246810,
    overwrite=YES
);

proc compare
    base=work._simple_first_run
    compare=rtcohrt.subject_rand_cohort101
    noprint;
run;
%let _simple_compare_sysinfo=&sysinfo;

%test_assert(condition=&_simple_compare_sysinfo=0,
             message=FIXED seed reproduces the identical SIMPLE table);


/*-----------------------------------------------------------------------
* Test 3: Two-arm BLOCK allocation and AUTO seed audit
*-----------------------------------------------------------------------*/
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=DRUG,
    cohort_no=102,
    method=BLOCK,
    sample_size=60,
    treatment_labels=%str(Treatment A|Treatment B),
    allocation=4 2,
    prefix=D,
    id_digits=5,
    id_shift=0,
    seed_mode=AUTO,
    overwrite=YES
);

%test_assert(
    condition=%sysfunc(exist(rtcohrt.drug_rand_cohort102)),
    message=BLOCK cohort dataset exists
);
%test_assert(
    condition=%sysfunc(exist(rtcohrt.drug_seed_cohort102)),
    message=AUTO mode creates a seed audit dataset
);

proc sql noprint;
    select count(*), count(distinct Block_No)
    into :_block_rows trimmed, :_block_count trimmed
    from rtcohrt.drug_rand_cohort102;

    create table work._block_counts as
    select Block_No, Treatment_Code, count(*) as N
    from rtcohrt.drug_rand_cohort102
    group by Block_No, Treatment_Code;

    select count(*) into :_bad_block_counts trimmed
    from work._block_counts
    where (Treatment_Code=1 and N ne 4)
       or (Treatment_Code=2 and N ne 2);

    select
        Seed,
        mod(floor(System_Relative_Time), 1000000)
    into
        :_auto_seed trimmed,
        :_expected_auto_seed trimmed
    from rtcohrt.drug_seed_cohort102;
quit;

%test_assert(condition=&_block_rows=60 and &_block_count=10,
             message=BLOCK cohort contains ten complete blocks);
%test_assert(condition=&_bad_block_counts=0,
             message=Every block contains exactly four A and two B records);
%test_assert(condition=&_auto_seed=&_expected_auto_seed,
             message=AUTO seed equals the last six relative-time digits);


/*-----------------------------------------------------------------------
* Test 4: Three-arm positional block allocation
*-----------------------------------------------------------------------*/
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=103,
    method=BLOCK,
    sample_size=30,
    treatment_labels=%str(A|B|C),
    allocation=2 2 2,
    prefix=S,
    id_digits=4,
    id_shift=0,
    seed_mode=FIXED,
    fixed_seed=135791,
    overwrite=YES
);

proc sql noprint;
    select count(distinct Block_No)
    into :_three_arm_blocks trimmed
    from rtcohrt.subject_rand_cohort103;

    create table work._three_arm_counts as
    select Block_No, Treatment_Code, count(*) as N
    from rtcohrt.subject_rand_cohort103
    group by Block_No, Treatment_Code;

    select count(*) into :_bad_three_arm_counts trimmed
    from work._three_arm_counts
    where N ne 2;
quit;

%test_assert(condition=&_three_arm_blocks=5,
             message=Allocation 2 2 2 derives block size six);
%test_assert(condition=&_bad_three_arm_counts=0,
             message=Every three-arm block contains two records per group);


/*-----------------------------------------------------------------------
* Test 5: RTF generation
*-----------------------------------------------------------------------*/
%generate_randomization_rtf(
    root_path=&test_root,
    table_type=DRUG,
    cohort_no=102,
    title1=Drug Randomization Test,
    title2=Cohort 102,
    overwrite=YES
);

%test_assert(
    condition=%sysfunc(
        fileexist(&test_root./cohort_info/drug_rand_cohort102.rtf)
    ),
    message=Drug BLOCK RTF output exists
);


/* Remove integration-test outputs after all assertions have completed. */
filename _testrtf
    "&test_root./cohort_info/drug_rand_cohort102.rtf";
data _null_;
    if fexist('_testrtf') then _rc=fdelete('_testrtf');
run;
filename _testrtf clear;

proc datasets lib=rtcohrt nolist nowarn;
    delete
        stratification_code
        subject_rand_cohort101 subject_seed_cohort101
        drug_rand_cohort102 drug_seed_cohort102
        subject_rand_cohort103 subject_seed_cohort103;
quit;


/* Final test status is easy to locate in the SAS log. */
%macro report_test_summary;
    %if &RT_TEST_FAILURES=0 %then
        %put NOTE: [TEST_SUMMARY] ALL VALID-PATH TESTS PASSED.;
    %else
        %put ERROR: [TEST_SUMMARY] &RT_TEST_FAILURES VALID-PATH TESTS FAILED.;
%mend report_test_summary;

%report_test_summary;
