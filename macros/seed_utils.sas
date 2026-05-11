/************************************************************************/
/* 内容：临床试验随机化种子工具宏                                          */
/* 作者：Industrial Generator (Codex)                                     */
/* 创建时间：2026/04/23                                                   */
/* 说明：                                                                  */
/*  - 统一管理随机种子生成、固定、校验与审计输出                           */
/*  - AUTO 模式下使用哈希派生整数种子，减少碰撞概率                        */
/************************************************************************/

%MACRO rt_assert(cond=, msg=);
    %if not (&cond) %then %do;
        %put ERROR: [RT_ASSERT] &msg;
        %abort cancel;
    %end;
%MEND rt_assert;

%MACRO rt_set_seed(
    seed_role=PLAN,                  /* PLAN / STRATA / OTHER */
    cohort_no=0,
    seed_mode=AUTO,                  /* AUTO / FIXED */
    fixed_seed=,
    out_seed_var=RT_SEED,
    out_time_var=RT_SEED_TIME
);
    %local _mode _seed_role;
    %let _mode=%upcase(&seed_mode);
    %let _seed_role=%upcase(&seed_role);

    %if &_mode = FIXED %then %do;
        %rt_assert(cond=%sysevalf(%superq(fixed_seed)^=,boolean),
                   msg=fixed_seed 不能为空(FIXED模式));
        %rt_assert(cond=%sysevalf(&fixed_seed > 0 and &fixed_seed < 2147483647),
                   msg=fixed_seed 需在(0,2147483647)内);

        data _null_;
            call symputx("&out_seed_var", &fixed_seed, 'g');
            call symputx("&out_time_var", put(datetime(), e8601dt19.), 'g');
            call symputx(cats("RT_SEED_ROLE_", "&_seed_role", "_COH", &cohort_no), &fixed_seed, 'g');
        run;
    %end;
    %else %if &_mode = AUTO %then %do;
        data _null_;
            length raw $200 md5hex $32;
            raw = cats(
                put(datetime(), e8601dt26.6), '|',
                symget('SYSJOBID'), '|',
                symget('SYSPROCESSID'), '|',
                symget('SYSUSERID'), '|',
                rand('uniform')
            );
            md5hex = put(md5(raw), $hex32.);
            seed = input(substr(md5hex, 1, 8), hex8.);
            if seed <= 0 then seed = 1357911;
            if seed >= 2147483647 then seed = 2147483646;

            call symputx("&out_seed_var", seed, 'g');
            call symputx("&out_time_var", put(datetime(), e8601dt19.), 'g');
            call symputx(cats("RT_SEED_ROLE_", "&_seed_role", "_COH", &cohort_no), seed, 'g');
        run;
    %end;
    %else %do;
        %put ERROR: seed_mode 仅支持 AUTO / FIXED; 
        %abort cancel;
    %end;

    %put NOTE: [Seed] role=&_seed_role cohort=&cohort_no mode=&_mode seed=&&&out_seed_var;
%MEND rt_set_seed;
