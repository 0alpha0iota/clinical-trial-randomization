%macro setpaths; *寻找文件路径的工具宏，不用管;
    %global _root;
    %local _fullpath _tmp _dir _rdir _pos;

    %let _fullpath = ;

    %if %symexist(_SASPROGRAMFILE) and %length(%superq(_SASPROGRAMFILE)) %then %do;
        %let _tmp      = %superq(_SASPROGRAMFILE);
        %let _fullpath = %sysfunc(dequote(&_tmp.));   
    %end;
    %else %do;
        %let _tmp = %sysfunc(getoption(sysin));
        %if %length(%superq(_tmp)) %then %let _fullpath = &_tmp;
        %else %do;
            %let _tmp      = %sysget(SAS_EXECFILEPATH);
            %let _fullpath = &_tmp;
        %end;
    %end;

    %if %length(%superq(_fullpath)) = 0 %then %do;
        %let _root = %sysfunc(pathname(work));
    %end;
    %else %do;
        %let _dir = %substr(
                        &_fullpath,
                        1,
                        %eval(%length(&_fullpath) - %length(%scan(&_fullpath,-1,'\')) - 1)
                     );
        %if %qsubstr(&_dir,%length(&_dir),1)=\ %then
            %let _dir = %qsubstr(&_dir,1,%eval(%length(&_dir)-1));

        %let _rdir = %sysfunc(reverse(&_dir));
        %let _pos  = %sysfunc(indexc(&_rdir,\));

        %if &_pos > 0 %then
            %let _root = %qsubstr(&_dir,1,%eval(%length(&_dir)-&_pos));
        %else
            %let _root = &_dir; 
    %end;
%mend;