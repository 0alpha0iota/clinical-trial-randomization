/**************************************************************************
* Rejection-path integration tests for the industrial framework.
*
* Expected RT_VALIDATION and RT_STRATA error messages are part of this test.
* A passing run ends with [TEST_SUMMARY] ALL REJECTION TESTS PASSED.
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


%macro test_assert(condition=, message=);
    %if not (&condition) %then %do;
        %put ERROR: [TEST_FAILURE] &message;
        %let RT_TEST_FAILURES=%eval(&RT_TEST_FAILURES+1);
    %end;
    %else %put NOTE: [TEST_PASS] &message;
%mend test_assert;


%rt_init_paths(root_path=&test_root);
proc datasets lib=rtcohrt nolist nowarn;
    delete
        subject_rand_cohort201 subject_seed_cohort201
        subject_rand_cohort202 subject_seed_cohort202
        drug_rand_cohort203 drug_seed_cohort203
        subject_rand_cohort204 subject_seed_cohort204
        subject_rand_cohort205 subject_seed_cohort205
        subject_rand_cohort206 subject_seed_cohort206
        subject_rand_cohort207 subject_seed_cohort207;
quit;


/* SIMPLE ratios must already be reduced. */
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=201,
    method=SIMPLE,
    sample_size=40,
    treatment_labels=%str(A|B),
    allocation=2:2,
    prefix=R,
    id_digits=4,
    seed_mode=AUTO,
    overwrite=YES
);
%test_assert(
    condition=not %sysfunc(exist(rtcohrt.subject_rand_cohort201)) and
              not %sysfunc(exist(rtcohrt.subject_seed_cohort201)),
    message=Non-reduced SIMPLE ratio is rejected before output
);


/* Exact simple totals require sample_size divisible by the ratio sum. */
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=202,
    method=SIMPLE,
    sample_size=25,
    treatment_labels=%str(A|B),
    allocation=1:1,
    prefix=R,
    id_digits=4,
    seed_mode=AUTO,
    overwrite=YES
);
%test_assert(
    condition=not %sysfunc(exist(rtcohrt.subject_rand_cohort202)) and
              not %sysfunc(exist(rtcohrt.subject_seed_cohort202)),
    message=Incompatible SIMPLE sample size is rejected before AUTO seed output
);


/* Block size is derived as 4+2=6; 20 is not divisible by six. */
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=DRUG,
    cohort_no=203,
    method=BLOCK,
    sample_size=20,
    treatment_labels=%str(A|B),
    allocation=4 2,
    prefix=D,
    id_digits=4,
    seed_mode=AUTO,
    overwrite=YES
);
%test_assert(
    condition=not %sysfunc(exist(rtcohrt.drug_rand_cohort203)) and
              not %sysfunc(exist(rtcohrt.drug_seed_cohort203)),
    message=Incomplete final block is rejected before AUTO seed output
);


/* Number of group labels must equal number of allocation values. */
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=204,
    method=BLOCK,
    sample_size=24,
    treatment_labels=%str(A|B|C),
    allocation=4 2,
    prefix=R,
    id_digits=4,
    seed_mode=FIXED,
    fixed_seed=12345,
    overwrite=YES
);
%test_assert(
    condition=not %sysfunc(exist(rtcohrt.subject_rand_cohort204)),
    message=Treatment and allocation count mismatch is rejected
);


/* ID shift plus sample size must fit inside the configured digit width. */
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=205,
    method=SIMPLE,
    sample_size=20,
    treatment_labels=%str(A|B),
    allocation=1:1,
    prefix=R,
    id_digits=2,
    id_shift=90,
    seed_mode=FIXED,
    fixed_seed=12345,
    overwrite=YES
);
%test_assert(
    condition=not %sysfunc(exist(rtcohrt.subject_rand_cohort205)),
    message=Insufficient ID digit capacity is rejected
);


/* PROC PLAN fixed seeds must be positive and below 2^31-1. */
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=206,
    method=SIMPLE,
    sample_size=20,
    treatment_labels=%str(A|B),
    allocation=1:1,
    prefix=R,
    id_digits=4,
    seed_mode=FIXED,
    fixed_seed=0,
    overwrite=YES
);
%test_assert(
    condition=not %sysfunc(exist(rtcohrt.subject_rand_cohort206)),
    message=Invalid FIXED seed is rejected
);


/* Duplicate treatment names are ambiguous and therefore invalid. */
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=206,
    method=SIMPLE,
    sample_size=20,
    treatment_labels=%str(A|a),
    allocation=1:1,
    prefix=R,
    id_digits=4,
    seed_mode=FIXED,
    fixed_seed=12345,
    overwrite=YES
);
%test_assert(
    condition=not %sysfunc(exist(rtcohrt.subject_rand_cohort206)),
    message=Case-insensitive duplicate treatment labels are rejected
);


/* Create a protected reference cohort, then verify overwrite=NO preserves it. */
%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=207,
    method=SIMPLE,
    sample_size=20,
    treatment_labels=%str(A|B),
    allocation=1:1,
    prefix=R,
    id_digits=4,
    seed_mode=FIXED,
    fixed_seed=11111,
    overwrite=YES
);

data work._protected_reference;
    set rtcohrt.subject_rand_cohort207;
run;

%generate_cohort_randomization(
    root_path=&test_root,
    table_type=SUBJECT,
    cohort_no=207,
    method=SIMPLE,
    sample_size=20,
    treatment_labels=%str(A|B),
    allocation=1:1,
    prefix=R,
    id_digits=4,
    seed_mode=FIXED,
    fixed_seed=22222,
    overwrite=NO
);

proc compare
    base=work._protected_reference
    compare=rtcohrt.subject_rand_cohort207
    noprint;
run;
%let _protected_compare_sysinfo=&sysinfo;

%test_assert(
    condition=&_protected_compare_sysinfo=0,
    message=overwrite=NO preserves an existing cohort dataset
);


/*
 * Ensure a valid codebook exists, then submit malformed input with
 * overwrite=YES. Validation must finish before the existing codebook is
 * replaced.
 */
%generate_stratification_code(
    root_path=&test_root,
    stratification_factors=%str(Age: >=60, <60|Gender: F, M),
    overwrite=YES
);

%generate_stratification_code(
    root_path=&test_root,
    stratification_factors=%str(Age: >=60, |Gender: F, M),
    overwrite=YES
);

proc sql noprint;
    select count(*) into :_preserved_strata_rows trimmed
    from rtcohrt.stratification_code;
quit;

%test_assert(
    condition=&_preserved_strata_rows=4,
    message=Malformed stratification input does not replace a valid codebook
);


/* Remove integration-test outputs after all assertions have completed. */
proc datasets lib=rtcohrt nolist nowarn;
    delete
        stratification_code
        subject_rand_cohort201 subject_seed_cohort201
        subject_rand_cohort202 subject_seed_cohort202
        drug_rand_cohort203 drug_seed_cohort203
        subject_rand_cohort204 subject_seed_cohort204
        subject_rand_cohort205 subject_seed_cohort205
        subject_rand_cohort206 subject_seed_cohort206
        subject_rand_cohort207 subject_seed_cohort207;
quit;


%macro report_test_summary;
    %if &RT_TEST_FAILURES=0 %then
        %put NOTE: [TEST_SUMMARY] ALL REJECTION TESTS PASSED.;
    %else
        %put ERROR: [TEST_SUMMARY] &RT_TEST_FAILURES REJECTION TESTS FAILED.;
%mend report_test_summary;

%report_test_summary;
