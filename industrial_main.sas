/**************************************************************************
* Program: industrial_main.sas
*
* Purpose
* -------
* Production driver for clinical-trial randomization table generation.
* This file contains configuration and macro calls only. Reusable logic is
* implemented in the macros directory.
*
* Safe execution
* --------------
* RUN_* switches default to NO. Review the configuration, select the
* required operations, and then change the relevant switches to YES.
**************************************************************************/


/*=========================================================================
* 1. RESOLVE PROJECT ROOT
*
* A caller may define ROOT before running this program. If ROOT is empty,
* the directory containing industrial_main.sas is used.
*=========================================================================*/
%global root;

%macro rt_resolve_project_root;
    %if not %sysevalf(%superq(root)=, boolean) %then %return;

    data _null_;
        length _program_path _resolved_root $2048;

        _program_path=symget('_SASPROGRAMFILE');
        if missing(_program_path) then
            _program_path=getoption('sysin');
        if missing(_program_path) then
            _program_path=sysget('SAS_EXECFILEPATH');

        _program_path=dequote(strip(_program_path));

        if not missing(_program_path) then
            _resolved_root=prxchange(
                's#[/\\][^/\\]+$##', 1, _program_path
            );
        else
            _resolved_root=pathname('work');

        call symputx('root', _resolved_root, 'g');
    run;
%mend rt_resolve_project_root;

%rt_resolve_project_root;
%put NOTE: [RT_MAIN] Project root: &root.;


/*=========================================================================
* 2. INCLUDE FRAMEWORK MODULES
*=========================================================================*/
%include "&root./macros/assertions.sas";
%include "&root./macros/seed_utils.sas";
%include "&root./macros/randomization_engine.sas";
%include "&root./macros/stratification.sas";
%include "&root./macros/reporting.sas";


/*=========================================================================
* 3. STUDY METADATA
*
* These values are available to customized titles and downstream reporting.
* The cohort engine itself does not depend on protocol-specific text.
*=========================================================================*/
%let protocol_name =XXXXXXXXXXXXXXXX;
%let protocol_number =XXXX-XX-XXX;
%let sponsor =XXXX有限公司;
%let producer =上海益临思医药开发有限公司;
%let document_version =V1.0;


/*=========================================================================
* 4. EXECUTION SWITCHES
*=========================================================================*/
%let RUN_STRATIFICATION=NO;
%let RUN_COHORT        =YES;
%let RUN_REPORT        =YES;


/*=========================================================================
* 5. OPTIONAL STRATIFICATION CODEBOOK
*
* The last factor changes fastest in the generated Cartesian product.
* Stratum sample sizes are intentionally supplied by the user elsewhere;
* this macro does not infer or recommend stratum weights.
*=========================================================================*/
%let stratification_factors=%str(
    Age: >=60, <60|
    Gender: F, M|
    Disease Type: A, B, C
);

/*=========================================================================
* 6. SINGLE-COHORT RANDOMIZATION
*
* SIMPLE syntax example:
*   method=SIMPLE
*   allocation=1:3
*
* BLOCK syntax example:
*   method=BLOCK
*   allocation=4 2
*
* For a stratified design, call this engine once per stratum after the
* user has supplied a valid sample size for each stratum.
*=========================================================================*/
%let table_type      =SUBJECT;
%let cohort_no       =1;
%let method          =BLOCK;
%let sample_size     =60;
%let treatment_labels=%str(Treatment A|Treatment B);
%let allocation      =4 2;
%let prefix          =R;
%let id_digits       =4;
%let id_shift        =100;
%let seed_mode       =AUTO;
%let fixed_seed      =;
%let overwrite       =YES;

/*=========================================================================
* 7. OPTIONAL RTF LISTING
*
* Subject listings sort by Rand_ID.
* Drug listings sort by Treatment_Code and then Rand_ID.
* BLOCK listings display the within-block position column.
*=========================================================================*/
%macro rt_execute_configured_steps;
    %if %upcase(&RUN_STRATIFICATION)=YES %then %do;
        %generate_stratification_code(
            root_path=&root,
            stratification_factors=&stratification_factors,
            overwrite=NO
        );
    %end;

    %if %upcase(&RUN_COHORT)=YES %then %do;
        %generate_cohort_randomization(
            root_path=&root,
            table_type=&table_type,
            cohort_no=&cohort_no,
            method=&method,
            sample_size=&sample_size,
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
            root_path=&root,
            table_type=&table_type,
            cohort_no=&cohort_no,
            title1=&protocol_name,
            title2=%str(Cohort &cohort_no Randomization Table),
            overwrite=&overwrite
        );
    %end;
%mend rt_execute_configured_steps;

%rt_execute_configured_steps;
