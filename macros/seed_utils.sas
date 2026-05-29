/************************************************************************/
/* 内容：临床试验随机化种子工具宏                                          */
/* 作者：Industrial Generator (Codex)                                     */
/* 创建时间：2026/04/23                                                   */
/* 说明：                                                                  */
/*  - 统一管理随机种子生成、固定、校验与审计输出                           */
/*  - AUTO 模式下使用哈希派生整数种子，减少碰撞概率                        */
/************************************************************************/

/* ------------------------------------------------------------------------ */
/* Macro: rt_assert                                                          */
/* Purpose for beginners:                                                    */
/*   SAS macros do not automatically stop when a bad parameter is supplied.  */
/*   This helper checks a condition. If the condition is false, it writes an */
/*   ERROR message to the SAS log and stops the program immediately.          */
/* Example:                                                                  */
/*   %rt_assert(cond=%sysevalf(&N > 0), msg=N must be positive);             */
/* ------------------------------------------------------------------------ */
%MACRO rt_assert(cond=, msg=);
    %if not (&cond) %then %do;
        %put ERROR: [RT_ASSERT] &msg;
        %abort cancel;
    %end;
%MEND rt_assert;

/* ------------------------------------------------------------------------ */
/* Macro: rt_set_seed                                                        */
/* Purpose for beginners:                                                    */
/*   A randomization list must be reproducible when audited. This macro      */
/*   creates or stores the random seed used by PROC PLAN.                    */
/*                                                                            */
/* How to use:                                                                */
/*   seed_mode=FIXED: use a user-specified seed for exact reproducibility.   */
/*   seed_mode=AUTO : derive a seed from run metadata when no fixed seed is  */
/*                    supplied. The generated seed is saved to macro vars.   */
/*                                                                            */
/* Important SAS concept:                                                     */
/*   call symputx(name, value, 'g') writes a DATA-step value into a global    */
/*   macro variable so later PROC PLAN code can reference it as &&Seed_...   */
/* ------------------------------------------------------------------------ */
%MACRO rt_set_seed(
    seed_role=PLAN,                  /* PLAN / STRATA / OTHER */
    cohort_no=0,
    seed_mode=AUTO,                  /* AUTO / FIXED */
    fixed_seed=,
    out_seed_var=RT_SEED,
    out_time_var=RT_SEED_TIME
);
    /* Normalize text parameters to uppercase so AUTO, auto, and Auto behave the same. */
    %local _mode _seed_role;
    %let _mode=%upcase(&seed_mode);
    %let _seed_role=%upcase(&seed_role);

    /* FIXED mode: production validation/QC can rerun the program and obtain the same list. */
    %if &_mode = FIXED %then %do;
        %rt_assert(cond=%sysevalf(%superq(fixed_seed)^=,boolean),
                   msg=fixed_seed 不能为空(FIXED模式));
        %rt_assert(cond=%sysevalf(&fixed_seed > 0 and &fixed_seed < 2147483647),
                   msg=fixed_seed 需在(0,2147483647)内);

        /* DATA _NULL_ performs calculations without creating a permanent dataset. */
        data _null_;
            /* Save the fixed seed and timestamp into global macro variables. */
            call symputx("&out_seed_var", &fixed_seed, 'g');
            call symputx("&out_time_var", put(datetime(), e8601dt19.), 'g');
            call symputx(cats("RT_SEED_ROLE_", "&_seed_role", "_COH", &cohort_no), &fixed_seed, 'g');
        run;
    %end;
    /* AUTO mode: build a seed from timestamp/job/user information, then hash it. */
    %else %if &_mode = AUTO %then %do;
        data _null_;
            length raw $200 md5hex $32;
            /* raw collects run-specific values; md5(raw) converts them to a compact fingerprint. */
            raw = cats(
                put(datetime(), e8601dt26.6), '|',
                symget('SYSJOBID'), '|',
                symget('SYSPROCESSID'), '|',
                symget('SYSUSERID'), '|',
                rand('uniform')
            );
            md5hex = put(md5(raw), $hex32.);
            /* Convert the first 8 hexadecimal characters into a numeric PROC PLAN seed. */
            seed = input(substr(md5hex, 1, 8), hex8.);
            if seed <= 0 then seed = 1357911;
            if seed >= 2147483647 then seed = 2147483646;

            /* Store generated seed values for the engine and audit dataset. */
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
