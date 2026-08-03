/**************************************************************************
* File: reporting.sas
*
* Public macro
* ------------
* %generate_randomization_rtf
*
* Reporting is intentionally separate from randomization generation. The
* permanent cohort dataset retains all engine variables, while PROC REPORT
* selects and orders only the columns needed for the operational listing.
**************************************************************************/
ods path work.templat(update) sashelp.tmplmst(read);
proc template;
	define style styles.three;
		parent = styles.default;

        /* 定义颜色：取消灰色、黄色背景，统一为白色 */
        class colors /
            "gheader" = cx000000
            "docbg" = cxFFFFFF
            "docfg" = cx000000
            "tableborder" = cxCCCCCC
            "headerbg" = cxFFFFFF  /* 原灰色→改为白色 */
            "headerfg" = cx000000
            "headerbgstrong" = cxFFFFFF  /* 原灰色→改为白色 */
            "headerfgstrong" = cx000000
            "headerbgemph" = cxFFFFFF  /* 原灰色→改为白色 */
            "headerfgemph" = cx0000FF
            "captionbg" = cxFFFFFF  /* 原灰色→改为白色 */
            "captionfg" = cx000000
            "databgstrong" = cxFFFFFF  /* 原灰色→改为白色 */
            "datafgstrong" = cx000000
            "notebg" = cxFFFFFF  /* 原黄色→改为白色（对应ODS RTF TEXT的背景） */
            "notefg" = cx000000  /* 原黄色文字→改为黑色（可选调整） */
            "databgemph" = cxF8F8F8
            "datafgemph" = cx0000FF
            "databg" = cxFFFFFF
            "datafg" = cx000000
            "batchfg" = cx000000
            "batchbg" = cxFFFFFF  /* 原灰色→改为白色 */
            "tablebg" = cxFFFFFF
            "proctitlefg" = cx000000
            "proctitlebg" = cxFFFFFF  /* 原灰色→改为白色 */
            "systitlefg" = cx000000
            "systitlebg" = cxFFFFFF  /* 原灰色→改为白色 */
            "bylinebg" = cxFFFFFF
            "bylinefg" = cx666666
            "contitlefg" = cx000000
            "confolderfg" = cx0000FF
            "conentryfg" = cx000000
            "contentbg" = cxFFFFFF
            "contentfg" = cx000000
            "link1" = cx0000FF
            "link2" = cx800080;
        
        /* 定义字体（保持原配置） */
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
        
        /* 图表颜色（保持原配置） */
        class GraphColors /
            "gheader" = cx000000;
        
        /* 表格样式（保持原配置） */
        replace table from output /
            frame=hsides;
        
        /* 颜色列表（保持原配置） */
        replace color_list / 'bgh'=white;
        
        /* 文档边距（保持原配置） */
        replace body from document /
            bottommargin = 20mm
            topmargin = 20mm
            rightmargin = 20mm
            leftmargin = 25mm;
    end;
run;


%macro generate_randomization_rtf(
    root_path=,
    table_type=SUBJECT,
    cohort_no=,
    output_file=,
    title1=,
    title2=,
    overwrite=NO,
    protocol_name=,
    protocol_sn=,
    sponsor=,
    producer=,
    subject_naming=Subject,
    cohort_name=,
    randomization_version=,
    simulation_label=%str(模拟/测试用)
);
    %local
        _rt_table_type _rt_dataset _rt_seed_dataset _rt_method
        _rt_method_display _rt_output_file _rt_overwrite
        _rt_has_strata _rt_has_sub_id _rt_strata_columns _rt_strata_by
        _rt_protocol_name _rt_protocol_sn _rt_sponsor _rt_producer
        _rt_subject_naming _rt_cohort_name _rt_randomization_version
        _rt_report_type_title _rt_seed_text _rt_datetime_text _rt_date_text
        _rt_group_names _rt_allocation_raw _rt_allocation_display _rt_block_length _rt_has_relative_time_char
        _rt_saved_papersize _rt_saved_orientation _rt_saved_date _rt_saved_number _rt_saved_byline
    ;

    %let _rt_table_type=%upcase(%superq(table_type));
    %let _rt_overwrite=%upcase(%superq(overwrite));

    %rt_init_paths(root_path=&root_path);
    %if &RT_PATH_READY ne 1 %then %return;

    %if &_rt_table_type ne SUBJECT and &_rt_table_type ne DRUG %then %do;
        %put ERROR: [RT_REPORT] table_type must be SUBJECT or DRUG.;
        %return;
    %end;

    %if %sysfunc(notdigit(%superq(cohort_no))) ne 0 or %sysevalf(&cohort_no < 1) %then %do;
        %put ERROR: [RT_REPORT] cohort_no must be a positive integer.;
        %return;
    %end;

    %let _rt_dataset=%sysfunc(lowcase(&_rt_table_type))_rand_cohort&cohort_no;
    %let _rt_seed_dataset=%sysfunc(lowcase(&_rt_table_type))_seed_cohort&cohort_no;

    %if not %sysfunc(exist(rtcohrt.&_rt_dataset)) %then %do;
        %put ERROR: [RT_REPORT] Dataset rtcohrt.&_rt_dataset does not exist.;
        %return;
    %end;

    %if %sysevalf(%superq(output_file)=, boolean) %then %let _rt_output_file=&RT_COHORT_PATH./&_rt_dataset..rtf;
    %else %let _rt_output_file=%sysfunc(dequote(%superq(output_file)));

    %if &_rt_overwrite ne YES and &_rt_overwrite ne NO %then %do;
        %put ERROR: [RT_REPORT] overwrite must be YES or NO.;
        %return;
    %end;

    %if &_rt_overwrite=NO and %sysfunc(fileexist(&_rt_output_file)) %then %do;
        %put ERROR: [RT_REPORT] &_rt_output_file already exists. Use overwrite=YES to replace it.;
        %return;
    %end;

    %let _rt_protocol_name=%superq(protocol_name);
    %if %sysevalf(%superq(_rt_protocol_name)=, boolean) %then %let _rt_protocol_name=%superq(title1);

    %let _rt_cohort_name=%superq(cohort_name);
    %if %sysevalf(%superq(_rt_cohort_name)=, boolean) %then %let _rt_cohort_name=%superq(title2);

    %let _rt_protocol_sn=%superq(protocol_sn);
    %if %sysevalf(%superq(_rt_protocol_sn)=, boolean) and %symexist(protocol_SN) %then %let _rt_protocol_sn=&protocol_SN;

    %let _rt_sponsor=%superq(sponsor);
    %if %sysevalf(%superq(_rt_sponsor)=, boolean) and %symexist(sponsor) %then %let _rt_sponsor=&sponsor;

    %let _rt_producer=%superq(producer);
    %if %sysevalf(%superq(_rt_producer)=, boolean) and %symexist(producer) %then %let _rt_producer=&producer;

    %let _rt_subject_naming=%superq(subject_naming);
    %if %sysevalf(%superq(_rt_subject_naming)=, boolean) %then %let _rt_subject_naming=Subject;

    %let _rt_randomization_version=%superq(randomization_version);
    %if %sysevalf(%superq(_rt_randomization_version)=, boolean) and %symexist(randomization_version) %then %let _rt_randomization_version=&randomization_version;
    %if %sysevalf(%superq(_rt_randomization_version)=, boolean) and %symexist(document_version) %then %let _rt_randomization_version=&document_version;

    proc sql noprint outobs=1;
        select Randomization_Method, Allocation_Spec
        into :_rt_method trimmed, :_rt_allocation_raw trimmed
        from rtcohrt.&_rt_dataset;
    quit;

    %let _rt_has_strata=0;
    %let _rt_has_sub_id=0;
    %let _rt_strata_columns=;
    %let _rt_strata_by=;

    proc sql noprint;
        select count(*) into :_rt_has_strata trimmed
        from dictionary.columns
        where libname='RTCOHRT' and memname="%upcase(&_rt_dataset)" and upcase(name)='STRATUM_NO';

        select count(*) into :_rt_has_sub_id trimmed
        from dictionary.columns
        where libname='RTCOHRT' and memname="%upcase(&_rt_dataset)" and upcase(name) in ('RAND_SUB_ID', 'ID_SUB_CHAR');

        select name into :_rt_strata_columns separated by ' '
        from dictionary.columns
        where libname='RTCOHRT' and memname="%upcase(&_rt_dataset)"
          and upcase(name) not in (
              'TABLE_TYPE','COHORT_NO','RANDOMIZATION_METHOD','RANDOMIZATION_SEQUENCE',
              'STRATUM_NO','STRATUM_LABEL','STRATUM_CODE','STRATUM_RANDOMIZATION_SEQUENCE',
              'RAND_NUM','RAND_ID','RAND_SUB_ID','ID_SUB_CHAR','TREATMENT_CODE','TREATMENT_GROUP',
              'ALLOCATION_SPEC','BLOCK_NO','POSITION_IN_BLOCK','ALLOCATION_POSITION'
          )
        order by varnum;
    quit;

    %if &_rt_has_strata > 0 %then %let _rt_strata_by=Stratum_No Stratum_Label &_rt_strata_columns;

    proc sql noprint;
        select distinct Treatment_Group into :_rt_group_names separated by ':'
        from rtcohrt.&_rt_dataset
        order by Treatment_Code;
    quit;

    data _null_;
        length _allocation_raw _allocation_display $500;
        _allocation_raw=symget('_rt_allocation_raw');
        _allocation_display=tranwrd(compbl(strip(_allocation_raw)), ' ', ':');
        call symputx('_rt_allocation_display', _allocation_display, 'l');
    run;

    %let _rt_block_length=;
    %if %upcase(&_rt_method)=BLOCK %then %do;
        proc sql noprint outobs=1;
            select max(Position_In_Block) into :_rt_block_length trimmed
            from rtcohrt.&_rt_dataset;
        quit;
    %end;

    %if %upcase(&_rt_method)=SIMPLE and &_rt_has_strata > 0 %then %let _rt_method_display=分层随机;
    %else %if %upcase(&_rt_method)=BLOCK and &_rt_has_strata > 0 %then %let _rt_method_display=分层区组随机;
    %else %if %upcase(&_rt_method)=SIMPLE %then %let _rt_method_display=简单随机;
    %else %if %upcase(&_rt_method)=BLOCK %then %let _rt_method_display=区组随机;
    %else %let _rt_method_display=&_rt_method;

    %let _rt_seed_text=;
    %let _rt_datetime_text=;
    %let _rt_date_text=;
    %if %sysfunc(exist(rtcohrt.&_rt_seed_dataset)) %then %do;
        %if &_rt_has_strata > 0 %then %do;
            %let _rt_seed_text=%str(各分层独立生成，见各分层表格下方注释);
            proc sql noprint outobs=1;
                select Production_Date_Character into :_rt_date_text trimmed
                from rtcohrt.&_rt_seed_dataset
                order by Stratum_No;
            quit;
        %end;
        %else %do;
            proc sql noprint;
                select count(*) into :_rt_has_relative_time_char trimmed
                from dictionary.columns
                where libname='RTCOHRT' and memname="%upcase(&_rt_seed_dataset)"
                  and upcase(name)='SYSTEM_RELATIVE_TIME_CHARACTER';
            quit;

            proc sql noprint outobs=1;
                %if &_rt_has_relative_time_char > 0 %then %do;
                    select Seed, System_Relative_Time_Character, Production_Date_Character
                    into :_rt_seed_text trimmed, :_rt_datetime_text trimmed, :_rt_date_text trimmed
                    from rtcohrt.&_rt_seed_dataset;
                %end;
                %else %do;
                    select Seed, strip(put(System_Relative_Time, 20.3)), Production_Date_Character
                    into :_rt_seed_text trimmed, :_rt_datetime_text trimmed, :_rt_date_text trimmed
                    from rtcohrt.&_rt_seed_dataset;
                %end;
            quit;
        %end;
    %end;

    %if %sysevalf(%superq(_rt_date_text)=, boolean) %then %let _rt_date_text=%sysfunc(today(), yymmdd10.);

    %if &_rt_table_type=SUBJECT %then %let _rt_report_type_title=&_rt_subject_naming.随机表;
    %else %let _rt_report_type_title=药物随机表;

    proc sort data=rtcohrt.&_rt_dataset out=work._rt_report_data;
        %if &_rt_has_strata > 0 %then %do;
            by &_rt_strata_by Rand_ID;
        %end;
        %else %if &_rt_table_type=SUBJECT %then %do;
            by Rand_ID;
        %end;
        %else %do;
            by Treatment_Code Rand_ID;
        %end;
    run;

    %let _rt_saved_papersize=%sysfunc(getoption(papersize, keyword));
    %let _rt_saved_orientation=%sysfunc(getoption(orientation, keyword));
    %let _rt_saved_date=%sysfunc(getoption(date));
    %let _rt_saved_number=%sysfunc(getoption(number));
    %let _rt_saved_byline=%sysfunc(getoption(byline));

    ods listing close;
    options papersize=A4 orientation=PORTRAIT nodate nonumber nobyline;
    ods escapechar='^';
    %if &_rt_has_strata > 0 %then %do;
        ods rtf file="&_rt_output_file" style=styles.three startpage=bygroup;
    %end;
    %else %do;
        ods rtf file="&_rt_output_file" style=styles.three;
    %end;

    ods rtf text= "^R/RTF'\b \pard\qc \fs28'&_rt_protocol_name.^R/RTF'\par'";
    ods rtf text= "^R/RTF'\b\pard \qc \fs28'&_rt_report_type_title.^R/RTF'\par'";

    %if not %sysevalf(%superq(_rt_cohort_name)=, boolean) %then %do;
        ods rtf text= "^R/RTF'\b\pard \qc \fs24'&_rt_cohort_name.^R/RTF'\par'";
    %end;

    ods rtf text= "方案编号： &_rt_protocol_sn.";
    ods rtf text= "申办单位：&_rt_sponsor.";
    ods rtf text= "产生日期： &_rt_date_text.";
    ods rtf text= "随机分配方法：&_rt_method_display.";
    ods rtf text= "随机种子数：&_rt_seed_text.";
    ods rtf text= "随机分配比例：&_rt_group_names. = &_rt_allocation_display.";

    %if %upcase(&_rt_method)=BLOCK %then %do;
        ods rtf text= "区组长度： &_rt_block_length.";
    %end;

    %if &_rt_has_strata > 0 %then %do;
        title4 "层号： #byval(Stratum_No)  层名： #byval(Stratum_Label)";
    %end;

    footnote
        J=L FONT=Tahoma HEIGHT=2.5 "保密"
        J=C FONT=Tahoma HEIGHT=2.5 " Page ^{THISPAGE} of ^{LASTPAGE}"
        J=R FONT=Tahoma HEIGHT=2.5 "&simulation_label.";

    proc report data=work._rt_report_data nowd missing split='|';
        %if &_rt_has_strata > 0 %then %do;
            by &_rt_strata_by;
        %end;

        %if &_rt_table_type=SUBJECT %then %do;
            %if %upcase(&_rt_method)=SIMPLE %then %do;
                columns Rand_ID Treatment_Group;
            %end;
            %else %if %upcase(&_rt_method)=BLOCK and &_rt_has_strata > 0 %then %do;
                columns Rand_ID %if &_rt_has_sub_id > 0 %then %do; Rand_Sub_ID %end; Stratum_No Block_No Position_In_Block Treatment_Group;
            %end;
            %else %if %upcase(&_rt_method)=BLOCK %then %do;
                columns Rand_ID %if &_rt_has_sub_id > 0 %then %do; Rand_Sub_ID %end; Block_No Position_In_Block Treatment_Group;
            %end;
            %else %do;
                columns Rand_ID Treatment_Group;
            %end;
        %end;
        %else %if &_rt_table_type=DRUG %then %do;
            %if %upcase(&_rt_method)=SIMPLE %then %do;
                columns Rand_ID Treatment_Group;
            %end;
            %else %if %upcase(&_rt_method)=BLOCK and &_rt_has_strata > 0 %then %do;
                columns Rand_ID Stratum_No Block_No Position_In_Block Treatment_Group;
            %end;
            %else %if %upcase(&_rt_method)=BLOCK %then %do;
                columns Rand_ID Block_No Position_In_Block Treatment_Group;
            %end;
            %else %do;
                columns Rand_ID Treatment_Group;
            %end;
        %end;

        %if &_rt_table_type=SUBJECT %then %do;
            define Rand_ID / display "&_rt_subject_naming.随机号" center style(column)={cellwidth=1.1in};
            %if &_rt_has_sub_id > 0 %then %do;
                define Rand_Sub_ID / display "替补&_rt_subject_naming.随机号" center style(column)={cellwidth=1.5in};
            %end;
            define Treatment_Group / display width=30 "组别" center style(column)={cellwidth=10%};
        %end;
        %else %do;
            define Rand_ID / display "药物编号" center style(column)={cellwidth=1.5in};
            define Treatment_Group / display width=30 "组别" center style(column)={cellwidth=1.5in};
        %end;

        %if %upcase(&_rt_method)=BLOCK and &_rt_has_strata > 0 %then %do;
            define Stratum_No / display "层号" center style(column)={cellwidth=0.6in};
            define Block_No / display "层内区组号" center style(column)={cellwidth=1.0in};
            define Position_In_Block / display "区组内排序号" center style(column)={cellwidth=1.1in};
        %end;
        %else %if %upcase(&_rt_method)=BLOCK %then %do;
            define Block_No / display "区组号" center style(column)={cellwidth=10%};
            define Position_In_Block / display "区组内排序号" center style(column)={cellwidth=1.1in};
        %end;

    run;

    %if &_rt_has_strata > 0 %then %do;
        ods rtf text= "注：在分层随机化中，每个分层均有独立生成的随机种子。随机种子、相对时间和生成时间记录于 &_rt_seed_dataset. 数据集中。";
    %end;
    %else %do;
        ods rtf text= "注：随机种子由当前 SAS 系统相对时间（以秒为单位）的最后六位数字生成。当前相对时间为 &_rt_datetime_text.，故随机种子数为&_rt_seed_text..";
    %end;

    ods rtf text= "^R/RTF'\b\pard \ql \fs24'制作单位: &_rt_producer.^R/RTF'\par'";
    ods rtf text= "^R/RTF'\b\pard \ql \fs24'随机化方案版本号： &_rt_randomization_version.^R/RTF'\par'";

    ods rtf close;
    ods listing;
    options &_rt_saved_papersize &_rt_saved_orientation &_rt_saved_date &_rt_saved_number &_rt_saved_byline;
    title;
    footnote;

    proc datasets lib=work nolist nowarn;
        delete _rt_report_data;
    quit;

    %put NOTE: [RT_REPORT] Created &_rt_output_file..;
%mend generate_randomization_rtf;



