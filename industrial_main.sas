/************************************************************************/
/* 内容：工业级临床试验随机表生成主程序                                    */
/* 作者：Industrial Generator (Codex)                                     */
/* 创建时间：2026/04/23                                                   */
/* 更新日志：                                                              */
/*  - V2.0: 模块化、审计追踪、生产化参数校验、可复现随机种子               */
/* 使用说明：                                                              */
/*  1) 修改“GLOBAL SETTINGS”区参数                                         */
/*  2) 运行本程序                                                           */
/*  3) 结果输出在 blind_code_test/<run_date>/cohort_info                  */
/************************************************************************/


/* %MACRO locating previous-level folder of directory where program is stored */
/* save the path as &_root. */
/* Beginner note: this block is copied from the original main.sas. It lets the */
/* program find a default project root without hard-coding a local computer path. */
%MACRO setpaths;
%global _root  ;
%if %symexist(_SASPROGRAMFILE) %then %do;
    %let current_path = %sysfunc(reverse(%substr(
        %sysfunc(reverse(&_SASPROGRAMFILE)), 
        %eval(%index(%sysfunc(reverse(&_SASPROGRAMFILE)), /)) +1
    )));
    %let setup_= %upcase(&current_path.);
    %let curpath =%qsysfunc(ksubstr(%quote(&setup_),1,%eval(%sysfunc(klength(%quote(&setup_))) -  %sysfunc(klength(%sysfunc(kscan(%quote(&setup_),-1,'\'))))  -2 ) ))  ;

    /* remove possible quotes */
    %let curpath = %sysfunc(compress(&curpath., %str(%')));
    %let _root = %ksubstr(%quote(&curpath.),1,%eval(%kindex(%quote(&curpath.),%kscan(%quote(&curpath.),-1,\))-2));
%end;

%else %do;

    %let _fullpath=%sysfunc(getoption(sysin));
    %if "&_fullpath." eq "" %then %let _fullpath=%sysget(sas_execfilepath);
    %let _root=%ksubstr(%quote(&_fullpath.),1,%eval(%kindex(%quote(&_fullpath.),%kscan(%quote(&_fullpath.),-2,\))-2));
%end;
%MEND;
%setpaths;
%put &_root.; /* check path */

/* ============================== INCLUDE MACROS ============================== */
/* %include reads another SAS program into this program at run time. */
/* Keep macro definitions in separate files so the main driver remains short. */
%include "./macros/seed_utils.sas";
%include "./macros/randomization_engine.sas";

/* ============================= GLOBAL SETTINGS ============================== */
%let protocol_name = XXXXXXXXXXXXXXXX临床研究;
%let protocol_SN   = XXXXXXXX;
%let sponsor       = XXXXXXXX有限公司;
%let producer      = 上海益临思医药开发有限公司;
%let subject_naming= 参与者;
%let rand_doc_ver  = V2.0;

/* 默认沿用原main.sas逻辑：输出到程序所在目录的上一层目录 */
%let project_root = &_root.;

/* 初始化输出路径 */
/* This creates blind_code_test/<run_date>/cohort_info under project_root. */
%rt_init_paths(
    root_path=&project_root,
    output_folder=blind_code_test,
    run_date=
);

/* =============================== EXAMPLE CALL =============================== */
/* 该示例采用行业标准多因子分层：3*4=12组合分层，2组(4:2)，N=72 */
/* Beginner reading guide for the call below:                                */
/*   N=72                  total planned randomization records               */
/*   block_group_n=4 2      each block has 4 experimental + 2 control records */
/*   strata_hierarchy=...   factor levels expand to 12 combination strata     */
/*   strata_block_n=...     one block is assigned to each of the 12 strata     */
%randomization_table_industrial(
    type=subject,
    cohort_No=1,
    cohort_name=%str( ),
    randomization_method=STRATIFIED,
    N=72,
    block_group_n=4 2,
    group_name=%str(试验组|对照组),
    strata_hierarchy=%str(Age=18-40,41-60,>60|Region=North,South,East,West),
    strata_block_n=1 1 1 1 1 1 1 1 1 1 1 1,
    prefix=R,
    ID_add=0,
    sub_id_offset=100,
    rand_width=4,
    seed_mode_plan=AUTO,
    set_seed_plan=,
    seed_mode_strata=AUTO,
    set_seed_strata=,
    save_audit=Y
);

/* ============================ OPTIONAL EXTRA CALLS =========================== */
/*
多层分层示例：
strata_hierarchy = %str(Region=CN,US|Sex=M,F|Stage=II,III)
表示自动生成 2*2*2 = 8 个分层；
strata_block_n 需要提供8个整数，对应各组合分层的区组数。
*/
/*
%randomization_table_industrial(
    type=drug,
    cohort_No=1,
    randomization_method=STRATIFIED,
    N=96,
    block_group_n=1 1,
    group_name=%str(A|B),
    strata_hierarchy=%str(Region=CN,US|Sex=M,F|Stage=II,III),
    strata_block_n=2 2 2 2 1 1 3 3,
    prefix=D,
    rand_width=5,
    seed_mode_plan=FIXED,
    set_seed_plan=20260423,
    seed_mode_strata=FIXED,
    set_seed_strata=20260424,
    save_audit=Y
);
*/
