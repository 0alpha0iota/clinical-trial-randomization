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

/* ============================== INCLUDE MACROS ============================== */
%include "./macros/seed_utils.sas";
%include "./macros/randomization_engine.sas";

/* ============================= GLOBAL SETTINGS ============================== */
%let protocol_name = XXXXXXXXXXXXXXXX临床研究;
%let protocol_SN   = XXXXXXXX;
%let sponsor       = XXXXXXXX有限公司;
%let producer      = 上海益临思医药开发有限公司;
%let subject_naming= 参与者;
%let rand_doc_ver  = V2.0;

/* 可选：指定项目根目录。空值时默认 WORK 路径 */
%let project_root = ;

/* 初始化输出路径 */
%rt_init_paths(
    root_path=&project_root,
    output_folder=blind_code_test,
    run_date=
);

/* =============================== EXAMPLE CALL =============================== */
/* 该示例采用行业标准多因子分层：3*4=12组合分层，2组(4:2)，N=72 */
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
