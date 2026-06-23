%let test_root=D:\W1nn1e\Documents\innoclinic\Randomization\clinical-trial-randomization\wxy_test\test5;

libname rtcohrt "&test_root.\cohort_info";

proc export data=rtcohrt.subject_seed_cohort1
    outfile="&test_root.\test5_seed_audit.csv"
    dbms=csv
    replace;
run;

proc sql;
    create table work.seed_count as
    select count(*) as N, count(distinct Stratum_No) as Strata_N
    from rtcohrt.subject_seed_cohort1;
quit;

proc export data=work.seed_count
    outfile="&test_root.\test5_seed_audit_count.csv"
    dbms=csv
    replace;
run;
