/**************************************************************************
* File: reporting.sas
*
* Public macro
* ------------
* %generate_randomization_rtf
*
* Reporting is intentionally separate from randomization generation. The
* permanent cohort dataset retains all engine variables, while PROC REPORT
* selects and orders only the columns needed for the operational listing.
**************************************************************************/


%macro generate_randomization_rtf(
    root_path=,
    table_type=SUBJECT,
    cohort_no=,
    output_file=,
    title1=Randomization Table,
    title2=,
    overwrite=NO
);
    %local
        _rt_table_type
        _rt_dataset
        _rt_method
        _rt_output_file
        _rt_overwrite
    ;

    %let _rt_table_type=%upcase(%superq(table_type));
    %let _rt_overwrite=%upcase(%superq(overwrite));

    %rt_init_paths(root_path=&root_path);
    %if &RT_PATH_READY ne 1 %then %return;

    %if &_rt_table_type ne SUBJECT and &_rt_table_type ne DRUG %then %do;
        %put ERROR: [RT_REPORT] table_type must be SUBJECT or DRUG.;
        %return;
    %end;

    %if %sysfunc(notdigit(%superq(cohort_no))) ne 0 or
        %sysevalf(&cohort_no < 1) %then %do;
        %put ERROR: [RT_REPORT] cohort_no must be a positive integer.;
        %return;
    %end;

    %let _rt_dataset=%sysfunc(lowcase(&_rt_table_type))_rand_cohort&cohort_no;
    %if not %sysfunc(exist(rtcohrt.&_rt_dataset)) %then %do;
        %put ERROR: [RT_REPORT] Dataset rtcohrt.&_rt_dataset does not exist.;
        %return;
    %end;

    %if %sysevalf(%superq(output_file)=, boolean) %then
        %let _rt_output_file=&RT_COHORT_PATH./&_rt_dataset..rtf;
    %else
        %let _rt_output_file=%sysfunc(dequote(%superq(output_file)));

    %if &_rt_overwrite ne YES and &_rt_overwrite ne NO %then %do;
        %put ERROR: [RT_REPORT] overwrite must be YES or NO.;
        %return;
    %end;

    %if &_rt_overwrite=NO and %sysfunc(fileexist(&_rt_output_file)) %then %do;
        %put ERROR: [RT_REPORT] &_rt_output_file already exists. Use overwrite=YES to replace it.;
        %return;
    %end;

    proc sql noprint outobs=1;
        select Randomization_Method
        into :_rt_method trimmed
        from rtcohrt.&_rt_dataset;
    quit;

    /*
     * Subject listings are ordered by randomization ID. Drug listings are
     * ordered by treatment group first to support labeling and packaging.
     */
    proc sort data=rtcohrt.&_rt_dataset out=work._rt_report_data;
        %if &_rt_table_type=SUBJECT %then %do;
            by Rand_ID;
        %end;
        %else %do;
            by Treatment_Code Rand_ID;
        %end;
    run;

    ods escapechar='^';
    ods rtf file="&_rt_output_file" style=journal bodytitle;

    title1 "&title1";
    %if not %sysevalf(%superq(title2)=, boolean) %then %do;
        title2 "&title2";
    %end;

    proc report data=work._rt_report_data nowd missing split='|';
        %if &_rt_method=BLOCK %then %do;
            columns Rand_ID Treatment_Group Block_No Position_In_Block;
        %end;
        %else %do;
            columns Rand_ID Treatment_Group;
        %end;

        define Rand_ID / display width=20 'Randomization ID';
        define Treatment_Group / display width=30 'Treatment Group';

        %if &_rt_method=BLOCK %then %do;
            define Block_No / display width=10 'Block No.';
            define Position_In_Block / display width=16 'Çø×éÎ»ÖÃ';
        %end;
    run;

    ods rtf close;
    title;

    proc datasets lib=work nolist nowarn;
        delete _rt_report_data;
    quit;

    %put NOTE: [RT_REPORT] Created &_rt_output_file..;
%mend generate_randomization_rtf;
