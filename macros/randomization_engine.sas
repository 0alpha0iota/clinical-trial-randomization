/************************************************************************/
/* 内容：工业化临床试验随机表生成引擎                                     */
/* 作者：Industrial Generator (Codex)                                     */
/* 创建时间：2026/04/23                                                   */
/* 目标：                                                                  */
/*  - 支持 SIMPLE / BLOCKING / STRATIFIED                                  */
/*  - STRATIFIED支持行业标准多因子组合分层(自动笛卡尔组合)                  */
/*  - 维持主程序 output 结构: Rand_ID, Rand_sub_ID, Group, Group_Num 等     */
/*  - 增加参数校验、审计追踪、可复现种子管理，并保留PROC PLAN核心生成逻辑   */
/************************************************************************/

/* ------------------------------------------------------------------------ */
/* Macro: rt_init_paths                                                      */
/* Purpose for beginners:                                                    */
/*   Create the folder structure where output SAS datasets will be written.  */
/*   The macro creates two global macro variables used by later code:        */
/*     RT_PATH        = run-level folder, e.g. .../blind_code_test/2026-05-29 */
/*     RT_PATH_COHORT = dataset folder under RT_PATH/cohort_info             */
/*                                                                            */
/* SAS note:                                                                 */
/*   options dlcreatedir lets LIBNAME create a physical folder if missing.   */
/* ------------------------------------------------------------------------ */
%MACRO rt_init_paths(root_path=, output_folder=blind_code_test, run_date=);
    /* %global makes these path macro variables available outside this macro. */
    %global RT_ROOT RT_RUN_DATE RT_PATH RT_PATH_COHORT;

    /* If root_path is blank, default to SAS WORK; otherwise use the caller-supplied root. */
    %if %sysevalf(%superq(root_path)=,boolean) %then %let RT_ROOT=%sysfunc(pathname(work));
    %else %let RT_ROOT=&root_path;

    /* If run_date is blank, use today in ISO format (YYYY-MM-DD). */
    %if %sysevalf(%superq(run_date)=,boolean) %then %let RT_RUN_DATE=%sysfunc(date(),E8601DA.);
    %else %let RT_RUN_DATE=&run_date;

    %let RT_PATH=&RT_ROOT./&output_folder./&RT_RUN_DATE;
    %let RT_PATH_COHORT=&RT_PATH./cohort_info;

    options dlcreatedir;
    libname _rtmk1 "&RT_PATH";
    libname _rtmk1 clear;
    libname _rtmk2 "&RT_PATH_COHORT";
    libname _rtmk2 clear;
    options nodlcreatedir;

    %put NOTE: [Path] RT_PATH=&RT_PATH;
    %put NOTE: [Path] RT_PATH_COHORT=&RT_PATH_COHORT;
%MEND rt_init_paths;

/* ------------------------------------------------------------------------ */
/* Macro: rt_validate_inputs                                                 */
/* Purpose for beginners:                                                    */
/*   Check all user-supplied parameters before randomization starts.         */
/*   This is safer than discovering errors after a randomization list has    */
/*   already been generated.                                                 */
/*                                                                            */
/* Key checks:                                                               */
/*   - N must be positive.                                                   */
/*   - method must be SIMPLE, BLOCKING, or STRATIFIED.                       */
/*   - number of group labels must match number of allocation-ratio values.  */
/*   - for STRATIFIED, number of combination strata must match strata_block_n.*/
/* ------------------------------------------------------------------------ */
%MACRO rt_validate_inputs(
    randomization_method=,
    N=,
    block_group_n=,
    group_name=,
    strata_block_n=,
    strata_hierarchy=
);
    /* Local macro variables exist only inside this macro. */
    %local _meth _gcount _bcount _scount _sbcount;
    %let _meth=%upcase(&randomization_method);

    %rt_assert(cond=%sysevalf(&N > 0), msg=N 必须为正整数);
    %rt_assert(cond=%sysfunc(indexw(SIMPLE BLOCKING STRATIFIED, &_meth)) > 0,
               msg=randomization_method 仅支持 SIMPLE/BLOCKING/STRATIFIED);

    /* group_name uses | as delimiter, e.g. A|B|C. Count labels and ratio values. */
    %let _gcount=%sysfunc(countw(%superq(group_name),|));
    %let _bcount=%sysfunc(countw(%superq(block_group_n),%str( )));
    %rt_assert(cond=%sysevalf(&_gcount > 1), msg=group_name 至少提供2组);
    %rt_assert(cond=%sysevalf(&_gcount = &_bcount), msg=group_name 与 block_group_n 长度不一致);

    /* Verify every allocation-ratio number is positive. */
    data _null_;
        array _bn{&_bcount} (&block_group_n);
        do i=1 to dim(_bn);
            if _bn{i} <= 0 then call symputx('_RT_BAD_RATIO', 1, 'g');
        end;
    run;
    %if %symexist(_RT_BAD_RATIO) %then %do;
        %put ERROR: block_group_n 需为正整数数组;
        %abort cancel;
    %end;

    %if &_meth = STRATIFIED %then %do;
        %rt_assert(cond=%sysevalf(%superq(strata_hierarchy)^=,boolean),
                   msg=STRATIFIED 模式下必须提供 strata_hierarchy);
        /* Count final strata as product of factor level counts.
           Example: Age has 3 levels and Region has 4 levels => 3*4=12 strata. */
        data _null_;
            length _h $2000 _piece $500 _levels $500;
            _h = symget('strata_hierarchy');
            _fcount = countw(_h, '|');
            _product = 1;
            do _k = 1 to _fcount;
                /* Each _piece looks like Factor=Level1,Level2,... */
                _piece = scan(_h, _k, '|');
                _levels = scan(_piece, 2, '=');
                _lvn = countw(_levels, ',');
                if _lvn <= 0 then _lvn = 0;
                _product = _product * _lvn;
            end;
            call symputx('_scount', _product, 'l');
        run;
        %let _sbcount=%sysfunc(countw(%superq(strata_block_n),%str( )));
        %rt_assert(cond=%sysevalf(&_scount > 0), msg=STRATIFIED 需提供有效 strata_hierarchy);
        %rt_assert(cond=%sysevalf(&_scount = &_sbcount), msg=分层总数 与 strata_block_n 长度不一致);
    %end;
%MEND rt_validate_inputs;

/* ------------------------------------------------------------------------ */
/* Macro: rt_build_strata_from_hierarchy                                     */
/* Purpose for beginners:                                                    */
/*   Convert stratification factors into all possible combination strata.    */
/*                                                                            */
/* Input example:                                                            */
/*   strata_hierarchy=%str(Region=US,EU|Sex=M,F|Risk=Low,High)              */
/*                                                                            */
/* Output dataset _strata_meta:                                              */
/*   Stratum_Num  Stratum_Name                                               */
/*   1            Region=US|Sex=M|Risk=Low                                  */
/*   2            Region=US|Sex=M|Risk=High                                 */
/*   ...                                                                        */
/*                                                                            */
/* SAS concept: PROC SQL below performs a cartesian join to append each new  */
/* factor's levels onto all combinations already created.                    */
/* ------------------------------------------------------------------------ */
%MACRO rt_build_strata_from_hierarchy(
    strata_hierarchy=,
    out_ds=_strata_meta
);
    %local _fcount _i _factor _levels;
    %let _fcount=%sysfunc(countw(%superq(strata_hierarchy),|));
    %rt_assert(cond=%sysevalf(&_fcount > 0), msg=strata_hierarchy 不能为空);

    /* Start with one empty row; each factor expands this table by its number of levels. */
    data _rt_combo;
        length Stratum_Name $1000;
        Stratum_Name="";
        output;
    run;

    /* Loop over factors separated by |. */
    %do _i=1 %to &_fcount;
        %let _factor=%qscan(%superq(strata_hierarchy), &_i, |);
        %let _levels=%qscan(%superq(_factor), 2, =);
        %let _factor=%qscan(%superq(_factor), 1, =);
        %rt_assert(cond=%sysevalf(%superq(_factor)^=,boolean), msg=分层因子名称不能为空);
        %rt_assert(cond=%sysevalf(%superq(_levels)^=,boolean), msg=分层因子水平不能为空);

        /* Convert the comma-separated levels for the current factor into rows. */
        data _rt_levels;
            length _factor $100 _level $200;
            _factor="&_factor";
            do _idx=1 to countw("&_levels", ',');
                _level=strip(scan("&_levels", _idx, ','));
                if not missing(_level) then output;
            end;
            keep _factor _level;
        run;

        /* Cartesian join: existing combinations X current factor levels. */
        proc sql noprint;
            create table _rt_combo_new as
            select
                case
                    when a.Stratum_Name = "" then cats(b._factor, "=", b._level)
                    else cats(a.Stratum_Name, "|", b._factor, "=", b._level)
                end as Stratum_Name length=1000
            from _rt_combo as a, _rt_levels as b;
        quit;

        data _rt_combo;
            set _rt_combo_new;
        run;
    %end;

    data &out_ds;
        set _rt_combo;
        Stratum_Num=_n_;
    run;

    /* Clean temporary WORK datasets so reruns start from a clean workspace. */
    proc datasets lib=work nolist nowarn;
        delete _rt_combo _rt_combo_new _rt_levels;
    quit;
%MEND rt_build_strata_from_hierarchy;

/* ------------------------------------------------------------------------ */
/* Macro: randomization_table_industrial                                     */
/* Purpose for beginners:                                                    */
/*   Main reusable macro that creates a randomization table.                 */
/*                                                                            */
/* High-level flow:                                                          */
/*   1. Validate user inputs.                                                */
/*   2. Calculate block size and number of blocks.                           */
/*   3. Generate reproducible seeds.                                         */
/*   4. Use PROC PLAN to create randomized block/position records.           */
/*   5. Map PROC PLAN positions to treatment groups by allocation ratio.     */
/*   6. If STRATIFIED, assign randomized blocks to combination strata.       */
/*   7. Format randomization IDs and write output/audit datasets.            */
/* ------------------------------------------------------------------------ */
%MACRO randomization_table_industrial(
    type=subject,
    cohort_No=1,
    cohort_name=%str( ),
    randomization_method=STRATIFIED,
    N=,
    block_group_n=,
    group_name=,
    strata_block_n=,
    strata_hierarchy=%str( ),
    prefix=NA,
    ID_add=0,
    sub_id_offset=100,
    rand_width=4,
    seed_mode_plan=AUTO,
    set_seed_plan=,
    seed_mode_strata=AUTO,
    set_seed_strata=,
    save_audit=Y
);
    %local _meth _gcount _scount _blocksize _nblocks _total_blocks_req _i;
    %let _meth=%upcase(&randomization_method);

    %rt_validate_inputs(
        randomization_method=&_meth,
        N=&N,
        block_group_n=&block_group_n,
        group_name=&group_name,
        strata_block_n=&strata_block_n,
        strata_hierarchy=&strata_hierarchy
    );

    /* Block size is the sum of allocation counts inside one block.
       Example: block_group_n=4 2 => block size=6, ratio=2:1. */
    data _null_;
        array b_n{%sysfunc(countw(&block_group_n))} (&block_group_n);
        _bsize = sum(of b_n[*]);
        call symputx("_blocksize", _bsize);
    run;

    %if %sysfunc(mod(&N, &_blocksize)) = 0 %then %let _nblocks=%eval(&N / &_blocksize);
    %else %do;
        %put ERROR: N(&N) 不是区组大小(&_blocksize)整数倍。当前版本需满足该条件。;
        %abort cancel;
    %end;

    /* In stratified randomization, strata_block_n gives how many blocks go to each stratum. */
    %if &_meth = STRATIFIED %then %do;
        data _null_;
            array s_n{%sysfunc(countw(&strata_block_n))} (&strata_block_n);
            _s_total = sum(of s_n[*]);
            call symputx("_total_blocks_req", _s_total);
        run;
        %if &_nblocks ne &_total_blocks_req %then %do;
            %put ERROR: strata_block_n总区组(&_total_blocks_req)与N推导区组(&_nblocks)不一致。;
            %abort cancel;
        %end;
    %end;

    /* Generate/store the seed used by PROC PLAN for treatment allocation. */
    %rt_set_seed(
        seed_role=PLAN,
        cohort_no=&cohort_No,
        seed_mode=&seed_mode_plan,
        fixed_seed=&set_seed_plan,
        out_seed_var=Seed_&type._cohort&cohort_No._PLAN,
        out_time_var=Datetime_&type._cohort&cohort_No._PLAN
    );

    %if &_meth = STRATIFIED %then %do;
        /* Generate/store a separate seed used to randomize block-to-stratum assignment. */
        %rt_set_seed(
            seed_role=STRATA,
            cohort_no=&cohort_No,
            seed_mode=&seed_mode_strata,
            fixed_seed=&set_seed_strata,
            out_seed_var=Seed_&type._cohort&cohort_No._STRATA,
            out_time_var=Datetime_&type._cohort&cohort_No._STRATA
        );
    %end;

    /* group_name uses | as delimiter, e.g. A|B|C. Count labels and ratio values. */
    %let _gcount=%sysfunc(countw(%superq(group_name),|));
    %let _scount=0;

    /* Step 1: 使用PROC PLAN生成随机化基础表(遵循临床试验常用做法)
       PROC PLAN returns variables block and size. size is randomized within block,
       and later we translate size into the actual treatment group. */
    PROC PLAN seed=&&Seed_&type._cohort&cohort_No._PLAN;
        %if &_meth = SIMPLE %then %do;
            /* SIMPLE: 整体样本作为一个大区组，保持总体比例 */
            factors block=1 ordered size=&N / noprint;
        %end;
        %else %do;
            /* BLOCKING/STRATIFIED: 按区组大小生成随机排列 */
            factors block=&_nblocks ordered size=&_blocksize / noprint;
        %end;
        /* Save PROC PLAN output to temporary dataset _raw_plan. */
        output out=_raw_plan;
    RUN; quit;

    /* Step 2: 根据区组内序号(size)映射试验组别与组别编号
       Beginner example: if block_group_n=4 2, then size 1-4 => group 1,
       size 5-6 => group 2 within each block. */
    data _mapped_plan;
        set _raw_plan;
        length Group $200;

        /* Temporary arrays hold group labels and ratios without writing them as columns. */
        array g_names{&_gcount} $200 _temporary_ (
            %do _i=1 %to &_gcount;
                "%qscan(%superq(group_name), &_i, |)" %if &_i < &_gcount %then ,;
            %end;
        );
        array g_ratio{%sysfunc(countw(&block_group_n))} _temporary_ (&block_group_n);

        /* _idx is the selected group number; _sum_ratio is the cumulative cutoff. */
        _idx=1;
        _sum_ratio=g_ratio[1];

        %if &_meth = SIMPLE %then %do;
            /* SIMPLE: 将比例放大到总样本量，用PROC PLAN随机size映射组别 */
            _multiplier=&N / &_blocksize;
            _sum_ratio=g_ratio[1] * _multiplier;
            do while (size > _sum_ratio and _idx < &_gcount);
                _idx + 1;
                _sum_ratio + (g_ratio[_idx] * _multiplier);
            end;
            drop _multiplier;
        %end;
        %else %do;
            do while (size > _sum_ratio and _idx < &_gcount);
                _idx + 1;
                _sum_ratio + g_ratio[_idx];
            end;
        %end;

        /* Store human-readable treatment group label and numeric group code. */
        Group=g_names[_idx];
        Group_Num=_idx;
        drop _idx _sum_ratio;
    run;

    /* Step 3: 分层(如适用)
       For STRATIFIED mode, first generate all factor-combination strata, then
       randomly assign whole blocks to strata. This preserves treatment balance
       within each stratum according to the block design. */
    %if &_meth = STRATIFIED %then %do;
        %rt_build_strata_from_hierarchy(
            strata_hierarchy=&strata_hierarchy,
            out_ds=_strata_meta
        );

        /* Expand each stratum into as many rows as the number of blocks assigned to it. */
        data _strata_layout;
            length Stratum_Name $1000;
            _ord=0;
            set _strata_meta;
            _this_stratum_n=input(scan("&strata_block_n", Stratum_Num, ' '), best.);
            do _j=1 to _this_stratum_n;
                _ord+1;
                output;
            end;
            keep _ord Stratum_Num Stratum_Name;
        run;

        /* 使用PROC PLAN对区组号再次随机排序，然后按顺序映射至组合分层 */
        PROC PLAN seed=&&Seed_&type._cohort&cohort_No._STRATA;
            factors block_id=&_nblocks random / noprint;
            output out=_randomized_blocks;
        RUN; quit;

        data _randomized_blocks;
            set _randomized_blocks;
            _ord=_n_;
        run;

        proc sort data=_strata_layout; by _ord; run;
        /* Merge randomized block order with strata layout: this creates block -> stratum mapping. */
        data _block_map;
            merge _randomized_blocks(in=a) _strata_layout(in=b);
            by _ord;
            if a and b;
            drop _ord;
        run;

        proc sort data=_mapped_plan; by block; run;
        proc sort data=_block_map; by block_id; run;

        /* Attach stratum information back onto every subject/drug row in the plan. */
        data _temp_final;
            merge _mapped_plan(rename=(block=block_id)) _block_map;
            by block_id;
        run;

        proc sort data=_temp_final;
            by Stratum_Num block_id size;
        run;

        /* Create sequential IDs within each stratum. */
        data _final_data;
            set _temp_final;
            by Stratum_Num;
            retain _stratum_seq 0;
            if first.Stratum_Num then _stratum_seq=1;
            else _stratum_seq+1;
            ID_Num=&ID_add + (Stratum_Num * 1000) + _stratum_seq;
            block=block_id;
            drop _stratum_seq block_id;
        run;
    %end;
    %else %do;
        /* Non-stratified randomization: all records belong to one artificial stratum named ALL. */
        data _final_data;
            set _mapped_plan;
            Stratum_Num=1;
            Stratum_Name='ALL';
            ID_Num=&ID_add + _n_;
        run;
    %end;

    /* Step 4: 输出格式(保持原结构，增强可配置)
       This dataset is the main randomization table used by downstream teams. */
    data "&RT_PATH_COHORT/&type._cohort&cohort_No";
        set _final_data;
        length Rand_ID $20 Rand_sub_ID $20;

        /* cats() concatenates prefix and zero-padded numeric ID, e.g. R0001. */
        if "%upcase(&prefix)" ne "NA" then Rand_ID=cats("&prefix", put(ID_Num, z&rand_width..));
        else Rand_ID=put(ID_Num, z&rand_width..);

        if "%upcase(&prefix)" ne "NA" then Rand_sub_ID=cats("&prefix", put(ID_Num + &sub_id_offset, z&rand_width..));
        else Rand_sub_ID=put(ID_Num + &sub_id_offset, z&rand_width..);

        label Rand_ID     = "随机号"
              Rand_sub_ID = "替补随机号"
              Group       = "组别"
              Group_Num   = "组别编号"
              block       = "区组号"
              size        = "区组内序号"
              Stratum_Num = "分层编号"
              Stratum_Name= "分层名称"
              ID_Num      = "顺序编号";
    run;

    /* Sort output so subject lists are by randomization ID and drug lists by group then ID. */
    proc sort data="&RT_PATH_COHORT/&type._cohort&cohort_No";
        %if %upcase(&type) = SUBJECT %then %do;
            by ID_Num;
        %end;
        %else %if %upcase(&type) = DRUG %then %do;
            by Group_Num ID_Num;
        %end;
        %else %do;
            by ID_Num;
        %end;
    run;

    /* Optional audit dataset: captures parameters, seeds, user, timestamp, and SAS version. */
    %if %upcase(&save_audit)=Y %then %do;
        data "&RT_PATH/randomization_audit_cohort&cohort_No";
            length protocol_name $200 type $32 method $20 group_name $500 strata_hierarchy $1000;
            protocol_name = symget('protocol_name');
            type="&type";
            cohort_no=&cohort_No;
            method="&_meth";
            N=&N;
            block_group_n="&block_group_n";
            group_name="%superq(group_name)";
            strata_block_n="&strata_block_n";
            strata_hierarchy="%superq(strata_hierarchy)";
            seed_plan=&&Seed_&type._cohort&cohort_No._PLAN;
            seed_plan_time="&&Datetime_&type._cohort&cohort_No._PLAN";
            %if &_meth = STRATIFIED %then %do;
                seed_strata=&&Seed_&type._cohort&cohort_No._STRATA;
                seed_strata_time="&&Datetime_&type._cohort&cohort_No._STRATA";
            %end;
            else do;
                seed_strata=.;
                seed_strata_time='';
            end;
            executed_by = symget('SYSUSERID');
            executed_at = put(datetime(), e8601dt19.);
            sas_version = symget('SYSVLONG4');
            output;
        run;
    %end;

    /* Clean temporary WORK datasets so reruns start from a clean workspace. */
    proc datasets lib=work nolist nowarn;
        delete _raw_plan _mapped_plan _strata_layout _randomized_blocks
               _block_map _temp_final _final_data _strata_meta;
    quit;

    %put NOTE: [RT] &type 随机化表(&_meth) 已输出到 &RT_PATH_COHORT.;
%MEND randomization_table_industrial;
