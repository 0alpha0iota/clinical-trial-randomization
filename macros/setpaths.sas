%macro setpaths(level=1);
    /*
     * Resolve a project root from the currently running SAS program.
     *
     * level=1 means the parent folder of the program folder.
     * level=2 means the grandparent folder of the program folder.
     *
     * Example:
     *   program: <repo>/wxy_test/test4/test4.sas
     *   %setpaths(level=2) resolves _root=<repo>
     */
    %global _root;
    %local _fullpath _dir _i _level;

    %let _fullpath=;
    %let _level=&level;

    %if %sysfunc(notdigit(%superq(_level))) ne 0 or
        %sysevalf(&_level < 0) %then %do;
        %put ERROR: [SETPATHS] level must be a nonnegative integer.;
        %return;
    %end;

    %if %symexist(_SASPROGRAMFILE) and
        not %sysevalf(%superq(_SASPROGRAMFILE)=, boolean) %then %do;
        %let _fullpath=%sysfunc(dequote(%superq(_SASPROGRAMFILE)));
    %end;
    %else %do;
        %let _fullpath=%sysfunc(dequote(%sysfunc(getoption(sysin))));

        %if %sysevalf(%superq(_fullpath)=, boolean) %then
            %let _fullpath=%sysfunc(dequote(%sysget(SAS_EXECFILEPATH)));
    %end;

    %if %sysevalf(%superq(_fullpath)=, boolean) %then %do;
        %let _root=%sysfunc(pathname(work));
        %put WARNING: [SETPATHS] Program path was unavailable. _root=&_root.;
        %return;
    %end;

    /* Normalize slash direction for both SAS Enterprise Guide and batch. */
    %let _fullpath=%sysfunc(translate(%superq(_fullpath), /, \));

    /* Start with the folder containing the running program. */
    %let _dir=%qsubstr(
        %superq(_fullpath),
        1,
        %eval(%length(%superq(_fullpath)) -
              %length(%qscan(%superq(_fullpath), -1, /)) - 1)
    );

    /* Move up LEVEL parent folders. */
    %do _i=1 %to &_level;
        %let _dir=%qsubstr(
            %superq(_dir),
            1,
            %eval(%length(%superq(_dir)) -
                  %length(%qscan(%superq(_dir), -1, /)) - 1)
        );
    %end;

    %let _root=&_dir;
    %put NOTE: [SETPATHS] _root=&_root.;
%mend setpaths;
