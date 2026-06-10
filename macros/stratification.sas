/**************************************************************************
* File: stratification.sas
*
* Public macro
* ------------
* %generate_stratification_code
*
* Input grammar
* -------------
* Factor Name: Level 1, Level 2|Second Factor: A, B, C
*
* The pipe, colon, and comma characters are reserved delimiters.  The
* generated dataset contains the Cartesian product of factor levels, with
* the last factor changing fastest.
**************************************************************************/


%macro generate_stratification_code(
    root_path=,
    stratification_factors=,
    overwrite=NO,
    max_strata=10000
);
    %local
        _rt_overwrite
        _rt_duplicate_factors
        _rt_duplicate_variables
        _rt_duplicate_levels
        _rt_factor_index
        _rt_variable_name
        _rt_factor_label
        _rt_level_count
        _rt_variable_list
        _rt_stage_exists
    ;
    %global RT_STRATA_VALID RT_STRATA_COUNT RT_FACTOR_COUNT;

    %let RT_STRATA_VALID=0;
    %let RT_STRATA_COUNT=0;
    %let RT_FACTOR_COUNT=0;
    %let _rt_overwrite=%upcase(%superq(overwrite));

    %rt_init_paths(root_path=&root_path);
    %if &RT_PATH_READY ne 1 %then %do;
        %put ERROR: [RT_STRATA] Path initialization failed.;
        %return;
    %end;

    %if &_rt_overwrite ne YES and &_rt_overwrite ne NO %then %do;
        %put ERROR: [RT_STRATA] overwrite must be YES or NO.;
        %return;
    %end;

    %if %sysevalf(%superq(stratification_factors)=, boolean) %then %do;
        %put ERROR: [RT_STRATA] stratification_factors must not be empty.;
        %return;
    %end;

    %if &_rt_overwrite=NO and
        %sysfunc(exist(rtcohrt.stratification_code)) %then %do;
        %put ERROR: [RT_STRATA] rtcohrt.stratification_code already exists. Use overwrite=YES to replace it.;
        %return;
    %end;

    proc datasets lib=work nolist nowarn;
        delete _rt_strata_factors _rt_strata_levels
               _rt_duplicate_factors _rt_duplicate_variables
               _rt_duplicate_levels _rt_combo _rt_combo_next
               _rt_current_levels _rt_stratification_stage;
    quit;

    /*
     * Parse the specification into normalized factor metadata and a
     * factor-level table.  Variable_Name is V7-compatible; Factor_Name is
     * retained as the display label, including spaces such as Disease Type.
     */
    data
        work._rt_strata_factors(
            keep=Factor_No Factor_Name Variable_Name Level_Count
                 Factor_Key Variable_Key
        )
        work._rt_strata_levels(
            keep=Factor_No Factor_Name Variable_Name
                 Level_No Level_Value Level_Key
        )
    ;
        length
            _spec _piece _levels_text $32767
            Factor_Name $200
            Variable_Name $32
            Level_Value $500
            Factor_Key Variable_Key $200
            Level_Key $500
        ;

        _errors=0;
        _spec=strip(symget('stratification_factors'));
        _factor_count=countw(_spec, '|', 'm');

        if _factor_count < 1 then do;
            put 'ERROR: [RT_STRATA] No stratification factors were found.';
            _errors+1;
        end;

        do Factor_No=1 to _factor_count;
            _piece=strip(scan(_spec, Factor_No, '|', 'm'));

            if missing(_piece) then do;
                put 'ERROR: [RT_STRATA] An empty factor definition was found.';
                _errors+1;
                continue;
            end;

            if countc(_piece, ':') ne 1 then do;
                put 'ERROR: [RT_STRATA] Every factor must contain exactly one colon: ' _piece;
                _errors+1;
                continue;
            end;

            _colon_position=index(_piece, ':');
            Factor_Name=strip(substr(_piece, 1, _colon_position-1));
            _levels_text=strip(substr(_piece, _colon_position+1));

            if missing(Factor_Name) then do;
                put 'ERROR: [RT_STRATA] A factor name is empty.';
                _errors+1;
            end;

            if indexc(Factor_Name, '|:,')>0 then do;
                put 'ERROR: [RT_STRATA] Factor names cannot contain reserved delimiters: ' Factor_Name;
                _errors+1;
            end;

            if missing(_levels_text) then do;
                put 'ERROR: [RT_STRATA] Factor has no levels: ' Factor_Name;
                _errors+1;
            end;

            /*
             * Replace non-V7 characters by underscores. If a name contains
             * no usable Latin characters, assign Factor_<sequence>. The
             * original factor text remains available as the variable label.
             */
            Variable_Name=prxchange(
                's/[^A-Za-z0-9_]+/_/o', -1, strip(Factor_Name)
            );
            Variable_Name=prxchange('s/_+/_/o', -1, Variable_Name);

            if missing(compress(Variable_Name, '_')) then
                Variable_Name=cats('Factor_', Factor_No);
            else if notdigit(substr(Variable_Name, 1, 1))=0 then
                Variable_Name=cats('F_', Variable_Name);

            Variable_Name=substr(Variable_Name, 1, 32);
            Factor_Key=upcase(strip(Factor_Name));
            Variable_Key=upcase(strip(Variable_Name));
            Level_Count=countw(_levels_text, ',', 'm');

            if Level_Count < 1 then do;
                put 'ERROR: [RT_STRATA] Factor has no valid levels: ' Factor_Name;
                _errors+1;
            end;

            output work._rt_strata_factors;

            do Level_No=1 to Level_Count;
                Level_Value=strip(
                    scan(_levels_text, Level_No, ',', 'm')
                );
                Level_Key=upcase(Level_Value);

                if missing(Level_Value) then do;
                    put 'ERROR: [RT_STRATA] Empty level found for factor: ' Factor_Name;
                    _errors+1;
                end;
                output work._rt_strata_levels;
            end;
        end;

        call symputx('RT_FACTOR_COUNT', _factor_count, 'g');
        call symputx('_RT_STRATA_PARSE_ERRORS', _errors, 'g');
    run;

    /*
     * Duplicate checks use normalized case-insensitive keys. Duplicate
     * Variable_Name values are rejected because they would create an
     * ambiguous wide SAS dataset.
     */
    proc sql noprint;
        create table work._rt_duplicate_factors as
        select Factor_Key, count(*) as Duplicate_Count
        from work._rt_strata_factors
        group by Factor_Key
        having calculated Duplicate_Count > 1;

        create table work._rt_duplicate_variables as
        select Variable_Key, count(*) as Duplicate_Count
        from work._rt_strata_factors
        group by Variable_Key
        having calculated Duplicate_Count > 1;

        create table work._rt_duplicate_levels as
        select Factor_No, Level_Key, count(*) as Duplicate_Count
        from work._rt_strata_levels
        group by Factor_No, Level_Key
        having calculated Duplicate_Count > 1;

        select count(*) into :_rt_duplicate_factors trimmed
        from work._rt_duplicate_factors;
        select count(*) into :_rt_duplicate_variables trimmed
        from work._rt_duplicate_variables;
        select count(*) into :_rt_duplicate_levels trimmed
        from work._rt_duplicate_levels;
    quit;

    %if &_rt_duplicate_factors > 0 %then
        %put ERROR: [RT_STRATA] Duplicate factor names are not allowed.;
    %if &_rt_duplicate_variables > 0 %then
        %put ERROR: [RT_STRATA] Factor names resolve to duplicate SAS variable names.;
    %if &_rt_duplicate_levels > 0 %then
        %put ERROR: [RT_STRATA] Duplicate levels within a factor are not allowed.;

    /* Calculate the Cartesian-product size before generating combinations. */
    data _null_;
        set work._rt_strata_factors end=_last;
        retain _product 1;
        _product=_product*Level_Count;
        if _last then call symputx('RT_STRATA_COUNT', _product, 'g');
    run;

    %if %sysfunc(notdigit(%superq(max_strata))) ne 0 or
        %sysevalf(&max_strata < 1) %then %do;
        %put ERROR: [RT_STRATA] max_strata must be a positive integer.;
        %return;
    %end;

    %if &RT_STRATA_COUNT > &max_strata %then %do;
        %put ERROR: [RT_STRATA] Cartesian product contains &RT_STRATA_COUNT strata, exceeding max_strata=&max_strata..;
        %return;
    %end;

    %if &_RT_STRATA_PARSE_ERRORS=0 and
        &_rt_duplicate_factors=0 and
        &_rt_duplicate_variables=0 and
        &_rt_duplicate_levels=0 and
        &RT_STRATA_COUNT > 0 %then
        %let RT_STRATA_VALID=1;

    %if &RT_STRATA_VALID ne 1 %then %do;
        %put ERROR: [RT_STRATA] Stratification specification was rejected.;
        %return;
    %end;

    /*
     * Start with one empty combination. Each loop performs a Cartesian join
     * against one factor's levels. _Combo_Order guarantees deterministic
     * ordering with the last factor changing fastest.
     */
    data work._rt_combo;
        _Combo_Order=1;
    run;

    proc sql noprint;
        select Variable_Name
        into :_rt_variable_list separated by ' '
        from work._rt_strata_factors
        order by Factor_No;
    quit;

    %do _rt_factor_index=1 %to &RT_FACTOR_COUNT;
        proc sql noprint;
            select
                Variable_Name,
                quote(trim(Factor_Name), '"'),
                Level_Count
            into
                :_rt_variable_name trimmed,
                :_rt_factor_label trimmed,
                :_rt_level_count trimmed
            from work._rt_strata_factors
            where Factor_No=&_rt_factor_index;

            create table work._rt_current_levels as
            select Level_No, Level_Value
            from work._rt_strata_levels
            where Factor_No=&_rt_factor_index
            order by Level_No;
        quit;

        proc sql;
            create table work._rt_combo_next as
            select
                a.*,
                b.Level_Value as &_rt_variable_name
                    length=500
                    label=&_rt_factor_label,
                ((a._Combo_Order-1)*&_rt_level_count+b.Level_No)
                    as _New_Combo_Order
            from work._rt_combo as a,
                 work._rt_current_levels as b
            order by _New_Combo_Order;
        quit;

        data work._rt_combo;
            set work._rt_combo_next(
                drop=_Combo_Order
                rename=(_New_Combo_Order=_Combo_Order)
            );
        run;
    %end;

    data work._rt_stratification_stage;
        retain &_rt_variable_list
               Stratum_No Stratum_Label Stratum_Code;
        set work._rt_combo;

        length Stratum_Label $64 Stratum_Code $32;
        Stratum_No=_Combo_Order;
        Stratum_Label=cats('Stratum ', Stratum_No);
        Stratum_Code=cats('STRATUM_', put(Stratum_No, z6.));

        label
            Stratum_No='Stratum number'
            Stratum_Label='Stratum label'
            Stratum_Code='Stable stratum code'
        ;
        drop _Combo_Order;
    run;

    /* Promote through a physical staging member after successful creation. */
    proc datasets lib=rtcohrt nolist nowarn;
        delete _rt_strata_stage;
    quit;

    data rtcohrt._rt_strata_stage;
        set work._rt_stratification_stage;
    run;

    %let _rt_stage_exists=%sysfunc(exist(rtcohrt._rt_strata_stage));
    %if &_rt_stage_exists ne 1 %then %do;
        %put ERROR: [RT_STRATA] Unable to write the stratification staging dataset.;
        %return;
    %end;

    proc datasets lib=rtcohrt nolist nowarn;
        delete stratification_code;
        change _rt_strata_stage=stratification_code;
    quit;

    proc datasets lib=work nolist nowarn;
        delete _rt_strata_factors _rt_strata_levels
               _rt_duplicate_factors _rt_duplicate_variables
               _rt_duplicate_levels _rt_combo _rt_combo_next
               _rt_current_levels _rt_stratification_stage;
    quit;

    %put NOTE: [RT_STRATA] Created rtcohrt.stratification_code with &RT_STRATA_COUNT strata.;
%mend generate_stratification_code;
