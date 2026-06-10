/**************************************************************************
* File: assertions.sas
*
* Purpose
* -------
* Shared path initialization and input validation for the randomization
* framework.  The public cohort engine calls these utilities before it
* generates a seed or invokes PROC PLAN.
*
* Design rule
* -----------
* Validation errors are reported to the SAS log and returned through a
* status macro variable.  Invalid input does not terminate the whole SAS
* session, which allows an industrial driver program to handle several
* independent cohort requests in one run.
**************************************************************************/


/*-----------------------------------------------------------------------
* Macro: rt_init_paths
*
* Assigns the RTCOHRT library to <root_path>/cohort_info.  DLCREATEDIR is
* enabled only while the library is assigned, so the caller's SAS option
* is restored after this macro finishes.
*-----------------------------------------------------------------------*/
%macro rt_init_paths(root_path=);
    %local _rt_saved_dlcreatedir;
    %global RT_ROOT RT_COHORT_PATH RT_PATH_READY;

    %let RT_PATH_READY=0;

    %if %sysevalf(%superq(root_path)=, boolean) %then %do;
        %put ERROR: [RT_PATH] root_path must not be empty.;
        %return;
    %end;

    %let RT_ROOT=%sysfunc(dequote(%superq(root_path)));
    %let RT_COHORT_PATH=&RT_ROOT./cohort_info;
    %let _rt_saved_dlcreatedir=%sysfunc(getoption(dlcreatedir));

    options dlcreatedir;
    libname rtcohrt "&RT_COHORT_PATH";
    options &_rt_saved_dlcreatedir;

    %if %sysfunc(libref(rtcohrt)) ne 0 %then %do;
        %put ERROR: [RT_PATH] Unable to assign RTCOHRT to &RT_COHORT_PATH..;
        %return;
    %end;

    %let RT_PATH_READY=1;
    %put NOTE: [RT_PATH] Cohort output library: &RT_COHORT_PATH.;
%mend rt_init_paths;


/*-----------------------------------------------------------------------
* Macro: rt_validate_randomization_inputs
*
* Method-specific allocation syntax
* ---------------------------------
* SIMPLE: allocation=1:3 or allocation=2:3:3
* BLOCK : allocation=4 2 or allocation=2 2 2
*
* For SIMPLE, the ratio must already be reduced to its simplest integer
* form.  For BLOCK, every value is an exact treatment count within one
* block and their sum defines the block size.
*
* Returned global metadata
* ------------------------
* RT_INPUT_VALID       1 when every check passes, otherwise 0
* RT_ARM_COUNT         number of treatment groups
* RT_ALLOCATION_SUM    sum of the ratio/count values
* RT_BLOCK_SIZE        block size for BLOCK; missing for SIMPLE
* RT_NUMBER_OF_BLOCKS  number of blocks for BLOCK; 1 for SIMPLE
* RT_OUTPUT_DATASET    cohort randomization dataset member name
* RT_SEED_DATASET      AUTO seed audit dataset member name
*-----------------------------------------------------------------------*/
%macro rt_validate_randomization_inputs(
    table_type=,
    cohort_no=,
    method=,
    sample_size=,
    treatment_labels=,
    allocation=,
    prefix=,
    id_digits=,
    id_shift=,
    seed_mode=,
    fixed_seed=,
    overwrite=NO,
    output_lib=rtcohrt
);
    %global RT_INPUT_VALID RT_ARM_COUNT RT_ALLOCATION_SUM;
    %global RT_BLOCK_SIZE RT_NUMBER_OF_BLOCKS;
    %global RT_OUTPUT_DATASET RT_SEED_DATASET;

    %let RT_INPUT_VALID=0;
    %let RT_ARM_COUNT=.;
    %let RT_ALLOCATION_SUM=.;
    %let RT_BLOCK_SIZE=.;
    %let RT_NUMBER_OF_BLOCKS=.;
    %let RT_OUTPUT_DATASET=;
    %let RT_SEED_DATASET=;

    data _null_;
        length
            _table_type _method _seed_mode _overwrite $16
            _cohort_text _sample_text _digits_text _shift_text $64
            _fixed_seed_text $64
            _labels _allocation _allocation_clean $32767
            _label_i _label_j _token $500
            _prefix $200
            _output_name _seed_name $32
        ;
        array _allocation_values[100] _temporary_;

        _errors=0;

        _table_type=upcase(strip(symget('table_type')));
        _method=upcase(strip(symget('method')));
        _seed_mode=upcase(strip(symget('seed_mode')));
        _overwrite=upcase(strip(symget('overwrite')));
        _cohort_text=strip(symget('cohort_no'));
        _sample_text=strip(symget('sample_size'));
        _digits_text=strip(symget('id_digits'));
        _shift_text=strip(symget('id_shift'));
        _fixed_seed_text=strip(symget('fixed_seed'));
        _labels=strip(symget('treatment_labels'));
        _allocation=strip(symget('allocation'));
        _prefix=symget('prefix');

        /* Validate enumerated control parameters first. */
        if _table_type not in ('SUBJECT', 'DRUG') then do;
            put 'ERROR: [RT_VALIDATION] table_type must be SUBJECT or DRUG.';
            _errors+1;
        end;

        if _method not in ('SIMPLE', 'BLOCK') then do;
            put 'ERROR: [RT_VALIDATION] method must be SIMPLE or BLOCK.';
            _errors+1;
        end;

        if _seed_mode not in ('AUTO', 'FIXED') then do;
            put 'ERROR: [RT_VALIDATION] seed_mode must be AUTO or FIXED.';
            _errors+1;
        end;

        if _overwrite not in ('YES', 'NO') then do;
            put 'ERROR: [RT_VALIDATION] overwrite must be YES or NO.';
            _errors+1;
        end;

        /* Positive integer identifiers and sample size are mandatory. */
        if missing(_cohort_text) or notdigit(strip(_cohort_text)) then do;
            put 'ERROR: [RT_VALIDATION] cohort_no must be a positive integer.';
            _errors+1;
            _cohort_no=.;
        end;
        else do;
            _cohort_no=input(_cohort_text, best32.);
            if _cohort_no < 1 or _cohort_no ne int(_cohort_no) then do;
                put 'ERROR: [RT_VALIDATION] cohort_no must be a positive integer.';
                _errors+1;
            end;
        end;

        if missing(_sample_text) or notdigit(strip(_sample_text)) then do;
            put 'ERROR: [RT_VALIDATION] sample_size must be a positive integer.';
            _errors+1;
            _sample_size=.;
        end;
        else do;
            _sample_size=input(_sample_text, best32.);
            if _sample_size < 1 or _sample_size ne int(_sample_size) then do;
                put 'ERROR: [RT_VALIDATION] sample_size must be a positive integer.';
                _errors+1;
            end;
        end;

        /* Validate randomization ID construction parameters. */
        if missing(_digits_text) or notdigit(strip(_digits_text)) then do;
            put 'ERROR: [RT_VALIDATION] id_digits must be an integer from 1 to 12.';
            _errors+1;
            _id_digits=.;
        end;
        else do;
            _id_digits=input(_digits_text, best32.);
            if _id_digits < 1 or _id_digits > 12 or
               _id_digits ne int(_id_digits) then do;
                put 'ERROR: [RT_VALIDATION] id_digits must be an integer from 1 to 12.';
                _errors+1;
            end;
        end;

        if missing(_shift_text) then _shift_text='0';
        if notdigit(strip(_shift_text)) then do;
            put 'ERROR: [RT_VALIDATION] id_shift must be a nonnegative integer.';
            _errors+1;
            _id_shift=.;
        end;
        else do;
            _id_shift=input(_shift_text, best32.);
            if _id_shift < 0 or _id_shift ne int(_id_shift) then do;
                put 'ERROR: [RT_VALIDATION] id_shift must be a nonnegative integer.';
                _errors+1;
            end;
        end;

        if lengthn(_prefix) > 32 then do;
            put 'ERROR: [RT_VALIDATION] prefix must not exceed 32 characters.';
            _errors+1;
        end;

        if n(_sample_size, _id_digits, _id_shift)=3 then do;
            _largest_id=_id_shift+_sample_size;
            _largest_allowed=(10**_id_digits)-1;
            if _largest_id > _largest_allowed then do;
                put 'ERROR: [RT_VALIDATION] ID capacity exceeded. Increase id_digits or reduce id_shift/sample_size.';
                _errors+1;
            end;
        end;

        /* Validate treatment labels and reject empty or duplicate labels. */
        _arm_count=countw(_labels, '|', 'm');
        if _arm_count < 2 then do;
            put 'ERROR: [RT_VALIDATION] treatment_labels must contain at least two pipe-delimited groups.';
            _errors+1;
        end;
        else if _arm_count > dim(_allocation_values) then do;
            put 'ERROR: [RT_VALIDATION] No more than 100 treatment groups are supported.';
            _errors+1;
        end;

        do _i=1 to _arm_count;
            _label_i=strip(scan(_labels, _i, '|', 'm'));
            if missing(_label_i) then do;
                put 'ERROR: [RT_VALIDATION] treatment_labels contains an empty group label.';
                _errors+1;
            end;

            do _j=1 to _i-1;
                _label_j=strip(scan(_labels, _j, '|', 'm'));
                if upcase(_label_i)=upcase(_label_j) and not missing(_label_i) then do;
                    put 'ERROR: [RT_VALIDATION] Duplicate treatment label: ' _label_i;
                    _errors+1;
                end;
            end;
        end;

        /* Normalize and validate the method-specific allocation syntax. */
        if _method='SIMPLE' then do;
            _allocation_clean=compress(_allocation, ' ');
            if index(_allocation_clean, ':')=0 then do;
                put 'ERROR: [RT_VALIDATION] SIMPLE allocation must use colon syntax, for example 1:1 or 2:3:3.';
                _errors+1;
            end;
            _allocation_count=countw(_allocation_clean, ':', 'm');
            _allocation_delimiter=':';
            _allocation_modifier='m';
        end;
        else if _method='BLOCK' then do;
            _allocation_clean=strip(compbl(_allocation));
            if indexc(_allocation_clean, ':,')>0 then do;
                put 'ERROR: [RT_VALIDATION] BLOCK allocation must use space-separated counts, for example 4 2.';
                _errors+1;
            end;
            _allocation_count=countw(_allocation_clean, ' ');
            _allocation_delimiter=' ';
            _allocation_modifier='';
        end;
        else do;
            _allocation_count=0;
            _allocation_delimiter=' ';
            _allocation_modifier='';
        end;

        if _allocation_count ne _arm_count then do;
            put 'ERROR: [RT_VALIDATION] Treatment label count and allocation value count do not match.';
            _errors+1;
        end;

        _allocation_sum=0;
        _allocation_gcd=0;
        do _i=1 to min(_allocation_count, dim(_allocation_values));
            _token=strip(scan(
                _allocation_clean,
                _i,
                _allocation_delimiter,
                _allocation_modifier
            ));

            if missing(_token) or notdigit(strip(_token)) then do;
                put 'ERROR: [RT_VALIDATION] Every allocation value must be a positive integer.';
                _errors+1;
                _value=.;
            end;
            else do;
                _value=input(_token, best32.);
                if _value < 1 or _value ne int(_value) then do;
                    put 'ERROR: [RT_VALIDATION] Every allocation value must be a positive integer.';
                    _errors+1;
                end;
            end;

            if not missing(_value) and _value >= 1 then do;
                _allocation_values[_i]=_value;
                _allocation_sum+_value;

                /* Euclidean algorithm: SIMPLE ratios must have GCD=1. */
                if _allocation_gcd=0 then _allocation_gcd=_value;
                else do;
                    _a=_allocation_gcd;
                    _b=_value;
                    do while (_b ne 0);
                        _remainder=mod(_a, _b);
                        _a=_b;
                        _b=_remainder;
                    end;
                    _allocation_gcd=_a;
                end;
            end;
        end;

        if _method='SIMPLE' and _allocation_gcd > 1 then do;
            put 'ERROR: [RT_VALIDATION] SIMPLE allocation ratio must be reduced to its simplest form.';
            _errors+1;
        end;

        if _allocation_sum > 0 and not missing(_sample_size) then do;
            if mod(_sample_size, _allocation_sum) ne 0 then do;
                if _method='SIMPLE' then
                    put 'ERROR: [RT_VALIDATION] sample_size is incompatible with the SIMPLE allocation ratio.';
                else if _method='BLOCK' then
                    put 'ERROR: [RT_VALIDATION] sample_size must be divisible by the derived block size.';
                _errors+1;
            end;
        end;

        /* A FIXED seed is validated but is intentionally not audited. */
        if _seed_mode='FIXED' then do;
            if missing(_fixed_seed_text) or
               notdigit(strip(_fixed_seed_text)) then do;
                put 'ERROR: [RT_VALIDATION] fixed_seed must be a positive integer in FIXED mode.';
                _errors+1;
            end;
            else do;
                _fixed_seed=input(_fixed_seed_text, best32.);
                if _fixed_seed < 1 or _fixed_seed >= 2147483647 or
                   _fixed_seed ne int(_fixed_seed) then do;
                    put 'ERROR: [RT_VALIDATION] fixed_seed must be an integer from 1 through 2147483646.';
                    _errors+1;
                end;
            end;
        end;

        /* Construct standardized SAS member names only after cohort_no parses. */
        if not missing(_cohort_no) and _table_type in ('SUBJECT', 'DRUG') then do;
            _output_name=cats(lowcase(_table_type), '_rand_cohort',
                              strip(put(_cohort_no, best32.)));
            _seed_name=cats(lowcase(_table_type), '_seed_cohort',
                            strip(put(_cohort_no, best32.)));

            if lengthn(_output_name)>32 or lengthn(_seed_name)>32 then do;
                put 'ERROR: [RT_VALIDATION] cohort_no produces a SAS dataset name longer than 32 characters.';
                _errors+1;
            end;
        end;

        if _errors=0 then do;
            call symputx('RT_INPUT_VALID', 1, 'g');
            call symputx('RT_ARM_COUNT', _arm_count, 'g');
            call symputx('RT_ALLOCATION_SUM', _allocation_sum, 'g');
            if _method='BLOCK' then do;
                call symputx('RT_BLOCK_SIZE', _allocation_sum, 'g');
                call symputx('RT_NUMBER_OF_BLOCKS',
                             _sample_size/_allocation_sum, 'g');
            end;
            else do;
                call symputx('RT_BLOCK_SIZE', ., 'g');
                call symputx('RT_NUMBER_OF_BLOCKS', 1, 'g');
            end;
            call symputx('RT_OUTPUT_DATASET', _output_name, 'g');
            call symputx('RT_SEED_DATASET', _seed_name, 'g');
        end;
        else call symputx('RT_INPUT_VALID', 0, 'g');
    run;

    /* Verify that the requested output library is currently usable. */
    %if &RT_INPUT_VALID %then %do;
        %if %sysfunc(libref(&output_lib)) ne 0 %then %do;
            %put ERROR: [RT_VALIDATION] Output library &output_lib is not assigned.;
            %let RT_INPUT_VALID=0;
        %end;
    %end;

    /*
     * A stale AUTO seed audit must never survive a FIXED overwrite.  For
     * that reason both standardized member names participate in collision
     * checking, regardless of the requested seed mode.
     */
    %if &RT_INPUT_VALID and %upcase(&overwrite)=NO %then %do;
        %if %sysfunc(exist(&output_lib..&RT_OUTPUT_DATASET)) %then %do;
            %put ERROR: [RT_VALIDATION] Output dataset &output_lib..&RT_OUTPUT_DATASET already exists. Use overwrite=YES to replace it.;
            %let RT_INPUT_VALID=0;
        %end;
        %if %sysfunc(exist(&output_lib..&RT_SEED_DATASET)) %then %do;
            %put ERROR: [RT_VALIDATION] Seed dataset &output_lib..&RT_SEED_DATASET already exists. Use overwrite=YES to replace it.;
            %let RT_INPUT_VALID=0;
        %end;
    %end;
%mend rt_validate_randomization_inputs;
