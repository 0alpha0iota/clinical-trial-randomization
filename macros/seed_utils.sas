/**************************************************************************
* File: seed_utils.sas
*
* Public macro
* ------------
* %generate_seed
*
* AUTO mode derives the PROC PLAN seed from the last six decimal digits
* of the current SAS system-relative datetime value.  SAS datetime values
* are elapsed seconds since 01JAN1960.  The raw value, production date,
* production datetime, and generated seed are retained in an audit dataset.
*
* FIXED mode accepts a designated validation seed.  It writes the seed to
* the SAS log and returns it in a macro variable, but intentionally creates
* no audit dataset.
**************************************************************************/


%macro generate_seed(
    table_type=,
    cohort_no=,
    seed_mode=AUTO,
    fixed_seed=,
    audit_out=,
    out_seed_var=RT_GENERATED_SEED,
    out_relative_time_var=RT_SEED_RELATIVE_TIME,
    out_date_var=RT_SEED_PRODUCTION_DATE,
    out_datetime_var=RT_SEED_PRODUCTION_DATETIME,
    out_valid_var=RT_SEED_VALID
);
    %local _rt_seed_mode;
    %global &out_seed_var &out_relative_time_var;
    %global &out_date_var &out_datetime_var &out_valid_var;

    %let &out_seed_var=;
    %let &out_relative_time_var=;
    %let &out_date_var=;
    %let &out_datetime_var=;
    %let &out_valid_var=0;
    %let _rt_seed_mode=%upcase(%superq(seed_mode));

    %if &_rt_seed_mode ne AUTO and &_rt_seed_mode ne FIXED %then %do;
        %put ERROR: [RT_SEED] seed_mode must be AUTO or FIXED.;
        %return;
    %end;

    %if &_rt_seed_mode=FIXED %then %do;
        %if %sysevalf(%superq(fixed_seed)=, boolean) %then %do;
            %put ERROR: [RT_SEED] fixed_seed is required in FIXED mode.;
            %return;
        %end;
        %if %sysfunc(notdigit(%superq(fixed_seed))) ne 0 %then %do;
            %put ERROR: [RT_SEED] fixed_seed must contain digits only.;
            %return;
        %end;
        %if %sysevalf(&fixed_seed < 1 or &fixed_seed >= 2147483647) %then %do;
            %put ERROR: [RT_SEED] fixed_seed must be from 1 through 2147483646.;
            %return;
        %end;

        %let &out_seed_var=&fixed_seed;
        %let &out_valid_var=1;
        %put NOTE: [RT_SEED] table_type=%upcase(&table_type) cohort=&cohort_no mode=FIXED seed=&fixed_seed.;
        %return;
    %end;

    /*
     * The integer portion is used deliberately: each decimal seed is the
     * last six digits of elapsed system seconds.  A zero result is changed
     * to one because PROC PLAN requires a positive seed.
     * Pause before AUTO generation so consecutive cohort calls do not use
     * the same integer second.
     */
    data _null_;
        call sleep(300, 0.01);
    run;

    data _null_;
        _produced_datetime=datetime();
        _relative_time=floor(_produced_datetime);
        _seed=mod(_relative_time, 1000000);
        if _seed=0 then _seed=1;

        call symputx("&out_seed_var", _seed, 'g');
        call symputx("&out_relative_time_var", _relative_time, 'g');
        call symputx("&out_date_var",
                     put(datepart(_produced_datetime), yymmdd10.), 'g');
        call symputx("&out_datetime_var",
                     put(_produced_datetime, e8601dt19.), 'g');
        call symputx("&out_valid_var", 1, 'g');
    run;

    /*
     * The cohort engine normally points audit_out to a temporary WORK
     * dataset and promotes it only after all integrity checks pass.
     */
    %if not %sysevalf(%superq(audit_out)=, boolean) %then %do;
        data &audit_out;
            length
                Table_Type $8
                Seed_Mode $5
                Production_Date_Character $10
                Production_Datetime_Character $19
                SAS_Version $64
                Executed_By $128
            ;

            Table_Type=upcase("&table_type");
            Cohort_No=&cohort_no;
            Seed_Mode='AUTO';
            Seed=&&&out_seed_var;
            System_Relative_Time=&&&out_relative_time_var;
            Production_Date=input("&&&out_date_var", yymmdd10.);
            Production_Datetime=input("&&&out_datetime_var", e8601dt19.);
            Production_Date_Character="&&&out_date_var";
            Production_Datetime_Character="&&&out_datetime_var";
            SAS_Version=symget('SYSVLONG4');
            Executed_By=symget('SYSUSERID');

            format Production_Date yymmdd10.
                   Production_Datetime e8601dt19.;

            label Seed='Generated random seed'
                  System_Relative_Time='Elapsed system seconds since 01JAN1960'
                  Production_Date='Seed production date'
                  Production_Datetime='Seed production datetime';
        run;
    %end;

    %put NOTE: [RT_SEED] table_type=%upcase(&table_type) cohort=&cohort_no mode=AUTO seed=&&&out_seed_var.;
%mend generate_seed;
