/**************************************************************************
* File: randomization_engine.sas
*
* Public macro
* ------------
* %generate_cohort_randomization
*
* This macro creates exactly one cohort randomization dataset.  It does
* not parse stratification factors and it does not allocate subjects among
* strata.  A stratified design calls this engine once for each stratum.
*
* PROC PLAN is the only random plan generator used by this engine.
**************************************************************************/


%macro generate_cohort_randomization(
    root_path=,
    table_type=SUBJECT,
    cohort_no=,
    method=,
    sample_size=,
    treatment_labels=,
    allocation=,
    prefix=,
    id_digits=5,
    id_shift=0,
    seed_mode=AUTO,
    fixed_seed=,
    overwrite=NO
);
    %local
        _rt_method
        _rt_seed_mode
        _rt_output_exists
        _rt_seed_exists
        _rt_row_count
        _rt_unique_id_count
        _rt_missing_group_count
        _rt_actual_group_rows
        _rt_unique_position_count
        _rt_audit_out
    ;

    %let _rt_method=%upcase(%superq(method));
    %let _rt_seed_mode=%upcase(%superq(seed_mode));
    %let _rt_actual_group_rows=0;
    %let _rt_audit_out=;
    %if &_rt_seed_mode=AUTO %then %let _rt_audit_out=work._rt_seed_audit;

    /* Assign or create <root_path>/cohort_info before validating members. */
    %rt_init_paths(root_path=&root_path);
    %if &RT_PATH_READY ne 1 %then %do;
        %put ERROR: [RT_ENGINE] Path initialization failed. No cohort was generated.;
        %return;
    %end;

    /*
     * All user-input checks, output collision checks, and derived design
     * calculations occur before seed generation and before PROC PLAN.
     */
    %rt_validate_randomization_inputs(
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
        overwrite=&overwrite,
        output_lib=rtcohrt
    );

    %if &RT_INPUT_VALID ne 1 %then %do;
        %put ERROR: [RT_ENGINE] Cohort &cohort_no was rejected before PROC PLAN.;
        %return;
    %end;

    /*
     * Remove only internal staging members left by an interrupted earlier
     * run.  Standardized production outputs are not touched until the new
     * plan has passed all integrity checks.
     */
    proc datasets lib=work nolist nowarn;
        delete _rt_seed_audit _rt_raw_plan _rt_randomization_stage
               _rt_expected_groups _rt_actual_groups _rt_group_check
               _rt_actual_block_groups _rt_unique_positions;
    quit;

    proc datasets lib=rtcohrt nolist nowarn;
        delete _rt_rand_stage _rt_seed_stage;
    quit;

    /*
     * AUTO audit data are initially written to WORK.  FIXED mode returns
     * the designated seed but creates no audit dataset.
     */
    %generate_seed(
        table_type=&table_type,
        cohort_no=&cohort_no,
        seed_mode=&seed_mode,
        fixed_seed=&fixed_seed,
        audit_out=&_rt_audit_out,
        out_seed_var=RT_PLAN_SEED,
        out_relative_time_var=RT_PLAN_RELATIVE_TIME,
        out_date_var=RT_PLAN_PRODUCTION_DATE,
        out_datetime_var=RT_PLAN_PRODUCTION_DATETIME,
        out_valid_var=RT_PLAN_SEED_VALID
    );

    %if &RT_PLAN_SEED_VALID ne 1 %then %do;
        %put ERROR: [RT_ENGINE] Seed generation failed. No cohort was generated.;
        %return;
    %end;

    /*
     * SIMPLE randomization:
     * The full cohort is one allocation set. PROC PLAN returns a random
     * permutation from 1 through sample_size. That position is mapped to
     * exact treatment totals derived from the simplified ratio.
     */
    %if &_rt_method=SIMPLE %then %do;
        proc plan seed=&RT_PLAN_SEED;
            factors Allocation_Position=&sample_size random / noprint;
            output out=work._rt_raw_plan;
        run;
        quit;
    %end;

    /*
     * BLOCK randomization:
     * Block_No remains ordered while Position_In_Block is randomized by
     * PROC PLAN. Treatment assignment is a deterministic cumulative range:
     * allocation=4 2 maps positions 1-4 to group 1 and 5-6 to group 2.
     */
    %else %if &_rt_method=BLOCK %then %do;
        proc plan seed=&RT_PLAN_SEED;
            factors
                Block_No=&RT_NUMBER_OF_BLOCKS ordered
                Position_In_Block=&RT_BLOCK_SIZE random
                / noprint;
            output out=work._rt_raw_plan;
        run;
        quit;
    %end;

    %if not %sysfunc(exist(work._rt_raw_plan)) %then %do;
        %put ERROR: [RT_ENGINE] PROC PLAN did not create its expected output dataset.;
        %return;
    %end;

    /*
     * Map each randomized PROC PLAN position to one treatment group.
     * Rand_Num always starts at id_shift+1 for every independent cohort.
     */
    data work._rt_randomization_stage;
        set work._rt_raw_plan;

        length
            Table_Type $8
            Randomization_Method $6
            Allocation_Spec $500
            Treatment_Group $200
            Rand_ID $64
            _allocation_text $32767
            _allocation_delimiter $1
            _prefix $200
        ;

        Table_Type=upcase("&table_type");
        Cohort_No=&cohort_no;
        Randomization_Method="&_rt_method";
        Allocation_Spec=symget('allocation');
        Randomization_Sequence=_n_;
        Rand_Num=&id_shift+Randomization_Sequence;

        _prefix=symget('prefix');
        Rand_ID=cats(_prefix, put(Rand_Num, z&id_digits..));

        if Randomization_Method='SIMPLE' then do;
            _allocation_text=compress(symget('allocation'), ' ');
            _allocation_delimiter=':';
            _allocation_position=Allocation_Position;
            _allocation_multiplier=&sample_size/&RT_ALLOCATION_SUM;
            Block_No=.;
            Position_In_Block=.;
        end;
        else do;
            _allocation_text=strip(compbl(symget('allocation')));
            _allocation_delimiter=' ';
            _allocation_position=Position_In_Block;
            _allocation_multiplier=1;
            Allocation_Position=.;
        end;

        Treatment_Code=.;
        _cumulative_count=0;

        do _arm=1 to &RT_ARM_COUNT;
            _arm_count=input(
                scan(
                    _allocation_text,
                    _arm,
                    _allocation_delimiter,
                    ifc(Randomization_Method='SIMPLE', 'm', '')
                ),
                best32.
            );
            _cumulative_count+(_arm_count*_allocation_multiplier);

            if missing(Treatment_Code) and
               _allocation_position <= _cumulative_count then
                Treatment_Code=_arm;
        end;

        Treatment_Group=strip(
            scan(symget('treatment_labels'), Treatment_Code, '|', 'm')
        );

        label
            Table_Type='Randomization table type'
            Cohort_No='Cohort number'
            Randomization_Method='Randomization method'
            Randomization_Sequence='Sequence in generated cohort table'
            Rand_Num='Numeric randomization number'
            Rand_ID='Randomization ID'
            Treatment_Code='Treatment group number'
            Treatment_Group='Treatment group'
            Allocation_Spec='Requested allocation'
            Block_No='Block number'
            Position_In_Block='Position within block'
            Allocation_Position='Random allocation position'
        ;

        drop
            _allocation_text _allocation_delimiter _prefix
            _allocation_position _allocation_multiplier
            _cumulative_count _arm _arm_count
        ;
    run;

    /*---------------------------------------------------------------
     * Post-generation integrity checks
     *
     * These checks detect PROC PLAN failures, accidental duplicate IDs,
     * unmapped treatment records, incorrect overall group counts, and
     * incorrect treatment counts within an individual block.
     *---------------------------------------------------------------*/
    %let RT_POSTCHECK_VALID=1;

    proc sql noprint;
        select
            count(*),
            count(distinct Rand_ID),
            sum(missing(Treatment_Group))
        into
            :_rt_row_count trimmed,
            :_rt_unique_id_count trimmed,
            :_rt_missing_group_count trimmed
        from work._rt_randomization_stage;
    quit;

    %if &_rt_row_count ne &sample_size %then %do;
        %put ERROR: [RT_INTEGRITY] Generated row count &_rt_row_count does not equal sample_size &sample_size..;
        %let RT_POSTCHECK_VALID=0;
    %end;

    %if &_rt_unique_id_count ne &sample_size %then %do;
        %put ERROR: [RT_INTEGRITY] Rand_ID values are not unique within the cohort.;
        %let RT_POSTCHECK_VALID=0;
    %end;

    %if %sysevalf(&_rt_missing_group_count > 0) %then %do;
        %put ERROR: [RT_INTEGRITY] At least one generated record has no treatment group.;
        %let RT_POSTCHECK_VALID=0;
    %end;

    /* Expected and actual total treatment counts must match exactly. */
    data work._rt_expected_groups;
        length Expected_Count 8;
        do Treatment_Code=1 to &RT_ARM_COUNT;
            _allocation_text=ifc(
                "&_rt_method"='SIMPLE',
                compress(symget('allocation'), ' '),
                strip(compbl(symget('allocation')))
            );
            _delimiter=ifc("&_rt_method"='SIMPLE', ':', ' ');
            _allocation_value=input(
                scan(
                    _allocation_text,
                    Treatment_Code,
                    _delimiter,
                    ifc("&_rt_method"='SIMPLE', 'm', '')
                ),
                best32.
            );

            if "&_rt_method"='SIMPLE' then
                Expected_Count=_allocation_value*
                               (&sample_size/&RT_ALLOCATION_SUM);
            else
                Expected_Count=_allocation_value*&RT_NUMBER_OF_BLOCKS;
            output;
        end;
        keep Treatment_Code Expected_Count;
    run;

    proc sql;
        create table work._rt_actual_groups as
        select Treatment_Code, count(*) as Actual_Count
        from work._rt_randomization_stage
        group by Treatment_Code;
    quit;

    proc sort data=work._rt_expected_groups;
        by Treatment_Code;
    run;
    proc sort data=work._rt_actual_groups;
        by Treatment_Code;
    run;

    data work._rt_group_check;
        merge work._rt_expected_groups(in=_expected)
              work._rt_actual_groups(in=_actual);
        by Treatment_Code;
        if not _expected or not _actual or Expected_Count ne Actual_Count then
            call symputx('RT_POSTCHECK_VALID', 0, 'l');
    run;

    %if &RT_POSTCHECK_VALID ne 1 %then
        %put ERROR: [RT_INTEGRITY] Overall treatment counts do not match the requested allocation.;

    /*
     * Verify random positions are a complete permutation. For BLOCK, also
     * verify every treatment count inside every block.
     */
    %if &_rt_method=SIMPLE %then %do;
        proc sort
            data=work._rt_randomization_stage(keep=Allocation_Position)
            out=work._rt_unique_positions
            nodupkey;
            by Allocation_Position;
        run;
    %end;
    %else %do;
        proc sort
            data=work._rt_randomization_stage(
                keep=Block_No Position_In_Block
            )
            out=work._rt_unique_positions
            nodupkey;
            by Block_No Position_In_Block;
        run;

        proc sql;
            create table work._rt_actual_block_groups as
            select
                Block_No,
                Treatment_Code,
                count(*) as Actual_Count
            from work._rt_randomization_stage
            group by Block_No, Treatment_Code;
        quit;

        data _null_;
            set work._rt_actual_block_groups end=_last;
            _allocation_text=strip(compbl(symget('allocation')));
            _expected=input(
                scan(_allocation_text, Treatment_Code, ' '),
                best32.
            );

            if Actual_Count ne _expected then
                call symputx('RT_POSTCHECK_VALID', 0, 'l');

            if _last then call symputx(
                '_rt_actual_group_rows', _n_, 'l'
            );
        run;

        %if &_rt_actual_group_rows ne %eval(&RT_NUMBER_OF_BLOCKS*&RT_ARM_COUNT) %then %do;
            %put ERROR: [RT_INTEGRITY] One or more blocks is missing a treatment group.;
            %let RT_POSTCHECK_VALID=0;
        %end;
    %end;

    %let _rt_unique_position_count=0;
    data _null_;
        if 0 then set work._rt_unique_positions nobs=_nobs;
        call symputx('_rt_unique_position_count', _nobs, 'l');
        stop;
    run;

    %if &_rt_unique_position_count ne &sample_size %then %do;
        %put ERROR: [RT_INTEGRITY] PROC PLAN positions are not unique and complete.;
        %let RT_POSTCHECK_VALID=0;
    %end;

    %if &RT_POSTCHECK_VALID ne 1 %then %do;
        %put ERROR: [RT_ENGINE] Integrity checks failed. No permanent cohort output was written.;
        proc datasets lib=work nolist nowarn;
            delete _rt_seed_audit _rt_raw_plan _rt_randomization_stage
                   _rt_expected_groups _rt_actual_groups _rt_group_check
                   _rt_actual_block_groups _rt_unique_positions;
        quit;
        %return;
    %end;

    /*
     * Write physical staging members only after validation and integrity
     * checks pass. Then standardize member names in one PROC DATASETS step.
     */
    data rtcohrt._rt_rand_stage;
        set work._rt_randomization_stage;
    run;

    %if &_rt_seed_mode=AUTO %then %do;
        data rtcohrt._rt_seed_stage;
            set work._rt_seed_audit;
            length Randomization_Dataset $32;
            Randomization_Dataset="&RT_OUTPUT_DATASET";
        run;
    %end;

    %let _rt_output_exists=%sysfunc(exist(rtcohrt._rt_rand_stage));
    %if &_rt_seed_mode=AUTO %then
        %let _rt_seed_exists=%sysfunc(exist(rtcohrt._rt_seed_stage));
    %else
        %let _rt_seed_exists=1;

    %if &_rt_output_exists ne 1 or &_rt_seed_exists ne 1 %then %do;
        %put ERROR: [RT_ENGINE] Unable to write staging datasets in &RT_COHORT_PATH..;
        proc datasets lib=rtcohrt nolist nowarn;
            delete _rt_rand_stage _rt_seed_stage;
        quit;
        %return;
    %end;

    proc datasets lib=rtcohrt nolist nowarn;
        delete &RT_OUTPUT_DATASET &RT_SEED_DATASET;
        change _rt_rand_stage=&RT_OUTPUT_DATASET;
        %if &_rt_seed_mode=AUTO %then %do;
            change _rt_seed_stage=&RT_SEED_DATASET;
        %end;
    quit;

    /* Remove WORK intermediates after successful promotion. */
    proc datasets lib=work nolist nowarn;
        delete _rt_seed_audit _rt_raw_plan _rt_randomization_stage
               _rt_expected_groups _rt_actual_groups _rt_group_check
               _rt_actual_block_groups _rt_unique_positions;
    quit;

    %put NOTE: [RT_ENGINE] Created rtcohrt..&RT_OUTPUT_DATASET with &sample_size records.;
    %if &_rt_seed_mode=AUTO %then
        %put NOTE: [RT_ENGINE] Created rtcohrt..&RT_SEED_DATASET for AUTO seed audit.;
    %else
        %put NOTE: [RT_ENGINE] FIXED seed was logged and no seed audit dataset was created.;
%mend generate_cohort_randomization;


/**************************************************************************
* Public macro: generate_stratified_rand
*
* Minimal first pass for stratified randomization:
* 1) create the stratum code table from factor levels
* 2) run the existing cohort engine independently inside each stratum
* 3) append all strata into the standard cohort output dataset
**************************************************************************/
%macro generate_stratified_rand(
    root_path=,
    table_type=SUBJECT,
    cohort_no=,
    method=,
    stratification_factors=,
    stratum_sample_sizes=,
    treatment_labels=,
    allocation=,
    prefix=,
    id_digits=5,
    id_shift=0,
    seed_mode=AUTO,
    fixed_seed=,
    overwrite=NO,
    max_strata=10000
);
    %local
        _rt_table_type
        _rt_output_dataset
        _rt_seed_dataset
        _rt_size_count
        _rt_size_errors
        _rt_stratum_no
        _rt_stratum_size
        _rt_running_shift
        _rt_total_n
    ;

    %let _rt_table_type=%upcase(%superq(table_type));
    %let _rt_output_dataset=%sysfunc(lowcase(&_rt_table_type))_rand_cohort&cohort_no;
    %let _rt_seed_dataset=%sysfunc(lowcase(&_rt_table_type))_seed_cohort&cohort_no;
    %let _rt_running_shift=&id_shift;
    %let _rt_total_n=0;

    %rt_init_paths(root_path=&root_path);
    %if &RT_PATH_READY ne 1 %then %return;

    %if %upcase(&overwrite)=NO and
        %sysfunc(exist(rtcohrt.&_rt_output_dataset)) %then %do;
        %put ERROR: [RT_STRATIFIED] Output dataset rtcohrt.&_rt_output_dataset already exists. Use overwrite=YES to replace it.;
        %return;
    %end;

    %generate_stratification_code(
        root_path=&root_path,
        stratification_factors=&stratification_factors,
        overwrite=&overwrite,
        max_strata=&max_strata
    );

    %if &RT_STRATA_VALID ne 1 %then %do;
        %put ERROR: [RT_STRATIFIED] Stratification code generation failed.;
        %return;
    %end;

    data work._rt_strata_code;
        set rtcohrt.stratification_code;
    run;

    %let _rt_size_count=%sysfunc(countw(%superq(stratum_sample_sizes), %str( )));
    %if &_rt_size_count ne &RT_STRATA_COUNT %then %do;
        %put ERROR: [RT_STRATIFIED] stratum_sample_sizes must have &RT_STRATA_COUNT values. Found &_rt_size_count..;
        %return;
    %end;

    data work._rt_stratum_sizes;
        length _sizes _token $32767;
        _sizes=symget('stratum_sample_sizes');
        _errors=0;
        do Stratum_No=1 to &RT_STRATA_COUNT;
            _token=strip(scan(_sizes, Stratum_No, ' '));
            Stratum_Sample_Size=input(_token, ?? best32.);
            if missing(_token) or missing(Stratum_Sample_Size) then do;
                put 'ERROR: [RT_STRATIFIED] Each stratum sample size must be a positive integer.';
                _errors+1;
            end;
            else do;
                if Stratum_Sample_Size < 1 or
                   Stratum_Sample_Size ne int(Stratum_Sample_Size) then do;
                    put 'ERROR: [RT_STRATIFIED] Each stratum sample size must be a positive integer.';
                    _errors+1;
                end;
            end;
            output;
        end;
        call symputx('_rt_size_errors', _errors, 'l');
        keep Stratum_No Stratum_Sample_Size;
    run;

    %if &_rt_size_errors ne 0 %then %return;

    proc datasets lib=work nolist nowarn;
        delete _rt_stratified_all _rt_one_stratum _rt_final_stratified
               _rt_seed_all _rt_one_seed _rt_final_seed;
    quit;

    %do _rt_stratum_no=1 %to &RT_STRATA_COUNT;
        proc sql noprint;
            select Stratum_Sample_Size
            into :_rt_stratum_size trimmed
            from work._rt_stratum_sizes
            where Stratum_No=&_rt_stratum_no;
        quit;

        %generate_cohort_randomization(
            root_path=&root_path,
            table_type=&table_type,
            cohort_no=&cohort_no,
            method=&method,
            sample_size=&_rt_stratum_size,
            treatment_labels=&treatment_labels,
            allocation=&allocation,
            prefix=&prefix,
            id_digits=&id_digits,
            id_shift=&_rt_running_shift,
            seed_mode=&seed_mode,
            fixed_seed=&fixed_seed,
            overwrite=YES
        );

        %if not %sysfunc(exist(rtcohrt.&_rt_output_dataset)) %then %do;
            %put ERROR: [RT_STRATIFIED] Stratum &_rt_stratum_no did not generate rtcohrt.&_rt_output_dataset..;
            %return;
        %end;

        data work._rt_one_stratum;
            if _n_=1 then
                set work._rt_strata_code(where=(Stratum_No=&_rt_stratum_no));
            set rtcohrt.&_rt_output_dataset(
                rename=(Randomization_Sequence=Stratum_Randomization_Sequence)
            );
            Randomization_Sequence=.;
            label Stratum_Randomization_Sequence='Sequence within stratum';
        run;

        proc append base=work._rt_stratified_all
                    data=work._rt_one_stratum force;
        run;

        %if %upcase(&seed_mode)=AUTO and
            %sysfunc(exist(rtcohrt.&_rt_seed_dataset)) %then %do;
            data work._rt_one_seed;
                if _n_=1 then
                    set work._rt_strata_code(where=(Stratum_No=&_rt_stratum_no));
                set rtcohrt.&_rt_seed_dataset;
            run;

            proc append base=work._rt_seed_all
                        data=work._rt_one_seed force;
            run;
        %end;

        %let _rt_running_shift=%eval(&_rt_running_shift + &_rt_stratum_size);
        %let _rt_total_n=%eval(&_rt_total_n + &_rt_stratum_size);
    %end;

    data work._rt_final_stratified;
        set work._rt_stratified_all;
        Randomization_Sequence=_n_;
        label Randomization_Sequence='Sequence in combined cohort table';
    run;

    %if %upcase(&seed_mode)=AUTO and %sysfunc(exist(work._rt_seed_all)) %then %do;
        data work._rt_final_seed;
            set work._rt_seed_all;
            length Randomization_Dataset $32;
            Randomization_Dataset="&_rt_output_dataset";
        run;
    %end;

    %rt_init_paths(root_path=&root_path);
    %if &RT_PATH_READY ne 1 %then %return;

    proc datasets lib=rtcohrt nolist nowarn;
        delete &_rt_output_dataset &_rt_seed_dataset;
    quit;

    data rtcohrt.&_rt_output_dataset;
        set work._rt_final_stratified;
    run;

    %if %upcase(&seed_mode)=AUTO and %sysfunc(exist(work._rt_final_seed)) %then %do;
        data rtcohrt.&_rt_seed_dataset;
            set work._rt_final_seed;
        run;
    %end;

    proc datasets lib=work nolist nowarn;
        delete _rt_strata_code _rt_stratum_sizes
               _rt_stratified_all _rt_one_stratum _rt_final_stratified
               _rt_seed_all _rt_one_seed _rt_final_seed;
    quit;

    %put NOTE: [RT_STRATIFIED] Created rtcohrt..&_rt_output_dataset with &_rt_total_n records across &RT_STRATA_COUNT strata.;
    %if %upcase(&seed_mode)=AUTO %then
        %put NOTE: [RT_STRATIFIED] Created rtcohrt..&_rt_seed_dataset with one seed audit row per stratum.;
%mend generate_stratified_rand;
