/************************************************************************/
/* 内容：创建临床试验随机表          */
/* 作者：张昊洋                      */
/* 创建时间：2026/03/04              */
/* 更新日志：                        */
/* 功能欠缺：多级分层 */
/************************************************************************/

/* %MACRO locating previous-level folder of directory where program is stored */
/* save the path as &_root. */
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

/* ========== GLOBAL SETTINGS (To Be Adjuested) ========== */

/* set working directory */
%let path =&_root.\blind_code_test\%sysfunc(date(),E8601DA.); * create output file naming after current date;
%let path2 = &path.\cohort_info; * create file storing .sas7bdat;
/*%let path3 = &path.\IWRS;*/ * if IRT output is needed;
/* create new folder */
options dlcreatedir;
libname folder1 "&path.";
libname folder1 clear;
libname folder2 "&path2.";
libname folder2 clear;
/*libname folder3 "&path3.";*/
/*libname folder3 clear;*/
options nodlcreatedir;

/* define global vars (trial recog info) */
%let protocol_name = XXXXXXXXXXXXXXXX临床研究;
%let protocol_SN = XXXXXXXX;	
%let sponsor = XXXXXXXX有限公司;	
%let producer = 上海益临思医药开发有限公司;
%let subject_naming = 参与者;
%let rand_doc_ver = V1.0;

/* defining render params of RTF output  */
PROC TEMPLATE;
    define style styles.three;
        parent=styles.default;
        
        /* color */
        class colors /
            "gheader" = cx000000
            "docbg" = cxFFFFFF
            "docfg" = cx000000
            "tableborder" = cxCCCCCC
            "headerbg" = cxF0F0F0
            "headerfg" = cx000000
            "headerbgstrong" = cxE0E0E0
            "headerfgstrong" = cx000000
            "headerbgemph" = cxE8E8E8
            "headerfgemph" = cx0000FF
            "captionbg" = cxF5F5F5
            "captionfg" = cx000000
            "databgstrong" = cxF0F0F0
            "datafgstrong" = cx000000
            "notebg" = cxFFFFE0
            "notefg" = cx808000
            "databgemph" = cxF8F8F8
            "datafgemph" = cx0000FF
            "databg" = cxFFFFFF
            "datafg" = cx000000
            "batchfg" = cx000000
            "batchbg" = cxF0F0F0
            "tablebg" = cxFFFFFF
            "proctitlefg" = cx000000
            "proctitlebg" = cxF0F0F0
            "systitlefg" = cx000000
            "systitlebg" = cxF0F0F0
            "bylinebg" = cxFFFFFF
            "bylinefg" = cx666666
            "contitlefg" = cx000000
            "confolderfg" = cx0000FF
            "conentryfg" = cx000000
            "contentbg" = cxFFFFFF
            "contentfg" = cx000000
            "link1" = cx0000FF
            "link2" = cx800080;
        
        /* font */
        class fonts /
            "TitleFont" = ("simsun", 12pt )
            "headingFont" = ("simsun", 11pt)
            "docFont" = ("simsun", 10pt )
            "footFont" = ("simsun", 10pt)
            "FixedStrongFont" = ("Courier New", 10pt, bold)
            "StrongFont" = ("simsun", 10pt, bold)
            "FixedEmphasisFont" = ("Courier New", 10pt, italic)
            "EmphasisFont" = ("simsun", 10pt, italic)
            "FixedFont" = ("Courier New", 10pt)
            "BatchFixedFont" = ("Courier New", 9pt)
            "TitleFont2" = ("simsun", 14pt, bold);
        
        /* graph color */
        class GraphColors /
            "gheader" = cx000000;
        
        /* table format */
        replace table from output /
            frame=hsides;
        
        /* color list */
        replace color_list / 'bgh'=white;
        
        /* doc margin */
        replace body from document /
            bottommargin = 20mm
            topmargin = 20mm
            rightmargin = 20mm
            leftmargin = 25mm;
    end;
RUN;

/* %MACRO preparing/cleaning operating environment */
%MACRO cleanup;
    %if "&sysprocessmode."="SAS DMS Session" %then %do;
        dm "log;clear;output;clear;odsresults;clear;";
    %end;
    %else %do;
        dm "log;clear;output;clear;";
    %end;
    proc datasets lib=work mt=data kill nolist nowarn;
    quit;
%MEND cleanup;

/* ========================= %MACRO generating random seed ============================ */
%MACRO _gen_seed(
					type= ,             /* subject / drug                  */
					coh_No = 0,         /* cohort number                   */
					purpose = ,         /* PLAN / STRATA                   */
					verify_seed = FALSE /* FALSE => time-based generation  */
					                    /* 'int' => fixed for verification */
					);

	%local _purpose _verify;
	%let _purpose = %upcase(&purpose);
	%let _verify = %upcase(&verify_seed);

	data &type._cohort&coh_No._seed_&_purpose;
		length type $32 purpose $12;
		call sleep(300, 0.01);  /* pause 3 sec */

		type      = "&type";
		cohort_no = &coh_no;
		purpose   = "&_purpose";

		datetime = datetime();

		%if "&_verify" = "FALSE" %then %do;
			/* time-based seed */
			systim10 = put(round(datetime, 0.1)*10, best.);
			seed_txt = substr(systim10, max(1,lengthn(systim10)-3));
      		seed     = input(seed_txt, best.);
		%end;
		%else %do;
			/* verification seed */
      		seed = &verify_seed;
    	%end;

		/* -------------------- pass to global macro vars -------------------- */
    	call symputx("Datetime_&type._cohort&coh_No._&_purpose", put(round(datetime,0.1),12.1), 'g');
    	call symputx("Seed_&type._cohort&coh_No._&_purpose",     seed, 'g');
    	call symputx("reportdate", left(put("&sysdate"d,yymmdd10.)), 'g');

    	keep type cohort_no purpose datetime seed;
	run;

%MEND _gen_seed;

/* ==================================== %MACRO generating randomization table ===========================================*/
%MACRO randomization_table(
            type = ,                      /* subject/drug                                                                  */
            cohort_No = ,                 /* cohort number                                                                 */
            cohort_name = %str( ),        /* 3rd title，can be used for dose level                                         */
            randomization_method = ,      /* SIMPLE/BLOCKING/STRATIFIED                                                    */
            N = ,                         /* total sample size involved                                                    */
            block_group_n = ,             /* sample dist. within 1 block, input array eg. 2 2 (block size 4)               */
            group_name = %str( ),         /* group naming, delimited by |                                                  */
            strata_block_n = ,            /* between-strata ratio, input array eg. 2 6                                     */
            strata_name= %str( ),         /* strata naming, delimited by |                                                 */
            prefix = NA,                  /* prefix of the rand ID, could be different across groups                       */
            ID_add = 0,                   /* shifting order of rand ID                                                     */
            set_seed_plan = FALSE,        /* FALSE/spec int, used for verification                                         */
            set_seed_strata = FALSE       /* random seed used for stratification                                           */
    );

    %local _meth _blocksize _nblocks _nstrata _total_blocks_req _i _gcount _scount;
    %let _meth = %upcase(&randomization_method);

    /* calculate number of groups and strata */
    %let _gcount = %sysfunc(countw(%quote(&group_name.), |));
    %let _scount = %sysfunc(countw(%quote(&strata_name.), |));

    /* calculate block size */
    data _null_;
        array b_n{%sysfunc(countw(&block_group_n.))} (&block_group_n.);
        _bsize = sum(of b_n[*]);
        call symputx("_blocksize", _bsize);
    run;

    /* Assertion: N must be the multiply of block size */
    %if %sysfunc(mod(&N., &_blocksize.)) = 0 %then %do;
        %let _nblocks = %eval(&N. / &_blocksize.);
    %end;
    %else %do;
        %put ERROR: 总样本量 N(&N) 不是区组大小(&_blocksize)的整数倍;
        %return;
    %end;

    /* Assertion: sum(strata_block_n) = Number of blocks */
    %if &_meth = STRATIFIED %then %do;
        data _null_;
            array s_n{%sysfunc(countw(&strata_block_n.))} (&strata_block_n.);
            _s_total = sum(of s_n[*]);
            call symputx("_total_blocks_req", _s_total);
        run;
        %if &_nblocks ^= &_total_blocks_req %then %do;
            %put ERROR: strata_block_n 指定的总区组数(&_total_blocks_req) 与 N 计算出的总区组数(&_nblocks) 不符！;
            %return;
        %end;
    %end;

    /* call MACRO _gen_seed */
    %_gen_seed(type=&type, coh_No=&cohort_No, purpose=PLAN, verify_seed=&set_seed_plan);
    %if &_meth = STRATIFIED %then %do;
        %_gen_seed(type=&type, coh_No=&cohort_No, purpose=STRATA, verify_seed=&set_seed_strata);
    %end;

    /* execute PROC PLAN for shuffled plan table */
    PROC PLAN seed=&&Seed_&type._cohort&cohort_No._PLAN;
        %if &_meth = SIMPLE %then %do;
		/* when SIMPLE, treat the entire sample as a single block */
            factors block=1 ordered size=&N. / noprint;
        %end;
        %else %do;
            factors block=&_nblocks. ordered size=&_blocksize. / noprint;
        %end;
        output out=_raw_plan;
    RUN; quit;

    /* map trial groups */
    data _mapped_plan;
        set _raw_plan;
        length Group $20;
        array g_names{&_gcount.} $300 _temporary_ (
            %do _i = 1 %to &_gcount.;
                "%sysfunc(scan(%quote(&group_name.), &_i, |))" %if &_i < &_gcount %then ,;
            %end;
        );
        array g_ratio{%sysfunc(countw(&block_group_n.))} _temporary_ (&block_group_n.);
        
        /* decide which group by 'size' - sort No. within a block */
        _idx = 1; _sum_ratio = g_ratio[1];
        %if &_meth = SIMPLE %then %do;
        /* when SIMPLE, scale up the ratio to sample size */
            _multiplier = &N. / &_blocksize.;
            _sum_ratio = g_ratio[1] * _multiplier;
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

        Group = g_names[_idx];
        Group_Num = _idx;
        drop _idx _sum_ratio;
    run;

    /* address STRATIFIED logic: shuffle and assign */
    %if &_meth = STRATIFIED %then %do;
        
        /* initiate strata layers */
        data _strata_layout;
            %do _i = 1 %to &_scount.;
                _this_stratum_n = %scan(&strata_block_n., &_i., %str( ));
                do _j = 1 to _this_stratum_n;
                    Stratum_Num = &_i.;
                    Stratum_Name = "%sysfunc(scan(%quote(&strata_name.), &_i., |))";
                    output;
                end;
            %end;
            drop _this_stratum_n _j;
        run;

        /* extract blocks and assign rand val (prepare for shuffle) */
        proc sort data=_mapped_plan(keep=block) out=_blocks_list nodupkey; by block; run;
        data _randomized_blocks;
            set _blocks_list;
            call streaminit(&&Seed_&type._cohort&cohort_No._STRATA); 
            _rand = rand("uniform"); /* generate random vals by Uni(0,1) */
        run;
        proc sort data=_randomized_blocks; by _rand; run;

        /* Assign: merge table sorted by rand vals and strata layers */
        data _block_map;
            merge _randomized_blocks _strata_layout;
            drop _rand;
            rename block = block_id;
        run;

        /* map back to plan */
        proc sort data=_mapped_plan; by block; run;
        proc sort data=_block_map; by block_id; run;

        data _temp_final;
            merge _mapped_plan(rename=(block=block_id)) _block_map;
            by block_id;
        run;

        /* sort by strata, block and size */
        proc sort data=_temp_final; 
            by Stratum_Num block_id size; 
        run;

        data _final_data;
            set _temp_final;
            by Stratum_Num;
            retain _stratum_seq 0;
            
            if first.Stratum_Num then _stratum_seq = 1;
            else _stratum_seq + 1;

            ID_Num = &ID_add. + (Stratum_Num * 1000) + _stratum_seq;
            rename block_id = block;
            drop _stratum_seq;
        run;
    %end;

    /* BLOCKS logic */
    %else %do;
        data _final_data;
            set _mapped_plan;
            Stratum_Num = 1; * Stratum_Num = 1 for randomization without stratifyng
            ID_Num = &ID_add. + _n_;
        run;
    %end;

    /* formatting Rand_ID and output dataset (TO BE ADJUSTED) */
    data "&path2.\&type._cohort&cohort_No.";
        set _final_data;

        length Rand_ID $10 Rand_sub_ID $10;
        if "&prefix" ^= "NA" then Rand_ID = cats("&prefix", put(ID_Num, z4.));
        else Rand_ID = put(ID_Num, z4.);
		if "&prefix" ^= "NA" then Rand_sub_ID = cats("&prefix", put(ID_Num + 100, z4.));
        else Rand_sub_ID = put(ID_Num + 100, z4.);
        
        label Rand_ID = "随机号"
			  Rand_sub_ID = "替补随机号"
              Group = "组别"
              Group_Num = "组别编号"
              block = "区组号"
              size = "区组内序号";
    run;

    /* output sorting (TO BE ADJUSTED) */
    proc sort data="&path2.\&type._cohort&cohort_No.";
        %if %upcase(&type) = SUBJECT %then %do;
            by ID_Num; 
        %end;
        %else %if %upcase(&type) = DRUG %then %do;
            by Group_Num ID_Num;
        %end;
    run;

    proc datasets lib=work nolist nowarn;
        delete _raw_plan _mapped_plan _strata_layout _blocks_list _randomized_blocks _block_map _temp_final _final_data;
    quit;

    %put NOTE: &type 随机化表(&randomization_method) 已成功生成至 &path2;

%MEND randomization_table;



%randomization_table(
						type = subject
						,cohort_no = 1
						,cohort_name = %str( )
						,randomization_method = STRATIFIED
						,N = 96
						,block_group_n = 4 2
						,group_name = %str(试验组|对照组)
						,strata_block_n = 2 7 7
						,strata_name = %str(PD层|PK采血层|非PK采血层)
						,prefix = R
						,ID_add = 0
						,set_seed_plan = FALSE
						,set_seed_strata = FALSE
						);




