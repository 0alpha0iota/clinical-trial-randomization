/************************************************************************/
/* 内容：工业化临床试验随机表生成引擎                                     */
/* 作者：Industrial Generator (Codex)                                     */
/* 创建时间：2026/04/23                                                   */
/* 目标：                                                                  */
/*  - 支持 SIMPLE / BLOCKING / STRATIFIED                                  */
/*  - STRATIFIED支持平铺分层与多层分层(自动笛卡尔组合)                      */
/*  - 维持主程序 output 结构: Rand_ID, Rand_sub_ID, Group, Group_Num 等     */
/*  - 增加参数校验、审计追踪、可复现种子管理                               */
/************************************************************************/

%MACRO rt_init_paths(root_path=, output_folder=blind_code_test, run_date=);
    %global RT_ROOT RT_RUN_DATE RT_PATH RT_PATH_COHORT;

    %if %sysevalf(%superq(root_path)=,boolean) %then %let RT_ROOT=%sysfunc(pathname(work));
    %else %let RT_ROOT=&root_path;

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

%MACRO rt_validate_inputs(
    randomization_method=,
    N=,
    block_group_n=,
    group_name=,
    strata_block_n=,
    strata_hierarchy=
);
    %local _meth _gcount _bcount _scount _sbcount;
    %let _meth=%upcase(&randomization_method);

    %rt_assert(cond=%sysevalf(&N > 0), msg=N 必须为正整数);
    %rt_assert(cond=%sysfunc(indexw(SIMPLE BLOCKING STRATIFIED, &_meth)) > 0,
               msg=randomization_method 仅支持 SIMPLE/BLOCKING/STRATIFIED);

    %let _gcount=%sysfunc(countw(%superq(group_name),|));
    %let _bcount=%sysfunc(countw(%superq(block_group_n),%str( )));
    %rt_assert(cond=%sysevalf(&_gcount > 1), msg=group_name 至少提供2组);
    %rt_assert(cond=%sysevalf(&_gcount = &_bcount), msg=group_name 与 block_group_n 长度不一致);

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
        data _null_;
            length _h $2000 _piece $500 _levels $500;
            _h = symget('strata_hierarchy');
            _fcount = countw(_h, '|');
            _product = 1;
            do _k = 1 to _fcount;
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

/* 生成多层分层组合：
   输入示例：strata_hierarchy=%str(Region=US,EU|Sex=M,F|Risk=Low,High)
   输出：_strata_meta (Stratum_Num, Stratum_Name)
*/
%MACRO rt_build_strata_from_hierarchy(
    strata_hierarchy=,
    out_ds=_strata_meta
);
    %local _fcount _i _factor _levels;
    %let _fcount=%sysfunc(countw(%superq(strata_hierarchy),|));
    %rt_assert(cond=%sysevalf(&_fcount > 0), msg=strata_hierarchy 不能为空);

    /* 初始化为单行空组合 */
    data _rt_combo;
        length Stratum_Name $1000;
        Stratum_Name="";
        output;
    run;

    %do _i=1 %to &_fcount;
        %let _factor=%qscan(%superq(strata_hierarchy), &_i, |);
        %let _levels=%qscan(%superq(_factor), 2, =);
        %let _factor=%qscan(%superq(_factor), 1, =);
        %rt_assert(cond=%sysevalf(%superq(_factor)^=,boolean), msg=分层因子名称不能为空);
        %rt_assert(cond=%sysevalf(%superq(_levels)^=,boolean), msg=分层因子水平不能为空);

        data _rt_levels;
            length _factor $100 _level $200;
            _factor="&_factor";
            do _idx=1 to countw("&_levels", ',');
                _level=strip(scan("&_levels", _idx, ','));
                if not missing(_level) then output;
            end;
            keep _factor _level;
        run;

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

    proc datasets lib=work nolist nowarn;
        delete _rt_combo _rt_combo_new _rt_levels;
    quit;
%MEND rt_build_strata_from_hierarchy;

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

    %rt_set_seed(
        seed_role=PLAN,
        cohort_no=&cohort_No,
        seed_mode=&seed_mode_plan,
        fixed_seed=&set_seed_plan,
        out_seed_var=Seed_&type._cohort&cohort_No._PLAN,
        out_time_var=Datetime_&type._cohort&cohort_No._PLAN
    );

    %if &_meth = STRATIFIED %then %do;
        %rt_set_seed(
            seed_role=STRATA,
            cohort_no=&cohort_No,
            seed_mode=&seed_mode_strata,
            fixed_seed=&set_seed_strata,
            out_seed_var=Seed_&type._cohort&cohort_No._STRATA,
            out_time_var=Datetime_&type._cohort&cohort_No._STRATA
        );
    %end;

    %let _gcount=%sysfunc(countw(%superq(group_name),|));
    %let _scount=0;

    /* Step 1: 生成区组模板(每个区组内组别占比) */
    data _block_template;
        length Group $200;
        retain seq_in_block 0;
        %do _i=1 %to &_gcount;
            do _k=1 to %scan(&block_group_n, &_i, %str( ));
                Group_Num=&_i;
                Group="%qscan(%superq(group_name), &_i, |)";
                seq_in_block+1;
                output;
            end;
        %end;
        drop _k;
    run;

    /* Step 2: 扩展为总样本，并在区组内随机排序 */
    data _raw_plan;
        do block=1 to &_nblocks;
            do _pt=1 to &_blocksize;
                set _block_template point=_pt nobs=nobs;
                size=seq_in_block;
                output;
            end;
        end;
        stop;
    run;

    data _mapped_plan;
        set _raw_plan;
        if _n_=1 then call streaminit(&&Seed_&type._cohort&cohort_No._PLAN);
        rand_plan = rand('uniform');
    run;
    proc sort data=_mapped_plan;
        by block rand_plan;
    run;

    data _mapped_plan;
        set _mapped_plan;
        by block;
        retain _size 0;
        if first.block then _size=1;
        else _size+1;
        size=_size;
        drop _size seq_in_block rand_plan;
    run;

    /* Step 3: 分层(如适用) */
    %if &_meth = STRATIFIED %then %do;
        %rt_build_strata_from_hierarchy(
            strata_hierarchy=&strata_hierarchy,
            out_ds=_strata_meta
        );

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

        proc sort data=_mapped_plan(keep=block) out=_blocks_list nodupkey;
            by block;
        run;

        data _randomized_blocks;
            set _blocks_list;
            if _n_=1 then call streaminit(&&Seed_&type._cohort&cohort_No._STRATA);
            _rand=rand('uniform');
        run;
        proc sort data=_randomized_blocks; by _rand; run;

        data _randomized_blocks;
            set _randomized_blocks;
            _ord=_n_;
            rename block=block_id;
        run;

        proc sort data=_strata_layout; by _ord; run;
        data _block_map;
            merge _randomized_blocks(in=a) _strata_layout(in=b);
            by _ord;
            if a and b;
            drop _rand _ord;
        run;

        proc sort data=_mapped_plan; by block; run;
        proc sort data=_block_map; by block_id; run;

        data _temp_final;
            merge _mapped_plan(rename=(block=block_id)) _block_map;
            by block_id;
        run;

        proc sort data=_temp_final;
            by Stratum_Num block_id size;
        run;

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
        data _final_data;
            set _mapped_plan;
            Stratum_Num=1;
            Stratum_Name='ALL';
            ID_Num=&ID_add + _n_;
        run;
    %end;

    /* Step 4: 输出格式(保持原结构，增强可配置) */
    data "&RT_PATH_COHORT/&type._cohort&cohort_No";
        set _final_data;
        length Rand_ID $20 Rand_sub_ID $20;

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

    proc datasets lib=work nolist nowarn;
        delete _block_template _raw_plan _mapped_plan _strata_layout _blocks_list
               _randomized_blocks _block_map _temp_final _final_data _strata_meta;
    quit;

    %put NOTE: [RT] &type 随机化表(&_meth) 已输出到 &RT_PATH_COHORT.;
%MEND randomization_table_industrial;
