# Industrial Clinical Trial Randomization Generator

This project is a reusable SAS 9.4 framework for generating controlled
clinical-trial randomization lists. The original `main.sas` is retained
unchanged as a reference implementation.

## Modules

- `industrial_main.sas`: configuration and execution driver
- `macros/assertions.sas`: paths, assertions, and input validation
- `macros/seed_utils.sas`: AUTO and FIXED random seed handling
- `macros/randomization_engine.sas`: one-cohort PROC PLAN engine
- `macros/stratification.sas`: Cartesian-product stratification codebook
- `macros/reporting.sas`: subject and drug RTF listings

## Output location

All SAS datasets are stored under:

```text
<root>/cohort_info
```

Standardized member names are:

```text
subject_rand_cohort<cohort_no>.sas7bdat
drug_rand_cohort<cohort_no>.sas7bdat
subject_seed_cohort<cohort_no>.sas7bdat
drug_seed_cohort<cohort_no>.sas7bdat
stratification_code.sas7bdat
```

Seed datasets are created only for `seed_mode=AUTO`.

## Single-cohort engine

### Simple randomization

Simple allocation uses a reduced colon-delimited ratio:

```sas
%generate_cohort_randomization(
    root_path=&root,
    table_type=SUBJECT,
    cohort_no=1,
    method=SIMPLE,
    sample_size=40,
    treatment_labels=%str(A|B),
    allocation=1:3,
    prefix=R,
    id_digits=5,
    id_shift=100,
    seed_mode=AUTO,
    overwrite=NO
);
```

The complete cohort is treated as one allocation set. `PROC PLAN` generates
a random permutation, and the engine maps it to exact treatment totals.

### Block randomization

Block allocation uses space-separated exact counts:

```sas
%generate_cohort_randomization(
    root_path=&root,
    table_type=DRUG,
    cohort_no=2,
    method=BLOCK,
    sample_size=60,
    treatment_labels=%str(A|B),
    allocation=4 2,
    prefix=D,
    id_digits=5,
    id_shift=0,
    seed_mode=FIXED,
    fixed_seed=314159,
    overwrite=NO
);
```

`allocation=4 2` defines a block size of six. Randomized positions 1 through
4 map to A, and positions 5 through 6 map to B. Treatment labels are not
shuffled independently.

## Validation

The engine rejects invalid requests before seed generation and `PROC PLAN`.
Checks include:

- valid table type, method, seed mode, and overwrite policy
- positive integer cohort number and sample size
- unique treatment labels
- positive integer allocation values
- reduced ratios for simple randomization
- exact compatibility between sample size and ratio or block size
- valid fixed seed range
- nonnegative ID shift and sufficient digit capacity
- existing output protection unless `overwrite=YES`

Post-generation checks verify row count, unique IDs, treatment totals,
randomized positions, and within-block treatment counts.

## Stratification codebook

Stratification is separate from the cohort engine:

```sas
%generate_stratification_code(
    root_path=&root,
    stratification_factors=%str(
        Age: >=60, <60|
        Gender: F, M|
        Disease Type: A, B, C
    ),
    overwrite=NO
);
```

The output contains 12 Cartesian-product rows. Factor names are converted to
safe SAS variable names, while original names are retained as labels.

Stratum weights and sample sizes are user-controlled. The current framework
does not infer, round, or recommend them. Each valid stratum is randomized by
calling the single-cohort engine independently.

## Seed policy

- `AUTO`: seed is the last six digits of the integer SAS system-relative
  datetime value. Seed, raw relative time, date, and datetime are audited.
- `FIXED`: designated seed is validated and logged. No seed audit dataset is
  created.

## RTF behavior

- Subject listings sort by `Rand_ID`.
- Drug listings sort by treatment group and then `Rand_ID`.
- Block listings display `Position_In_Block` as `区组内排序号`.
- Simple listings omit block-specific columns.

## Production qualification

The framework provides deterministic validation runs and traceable AUTO
seeds, but formal deployment still requires organization-specific SOPs,
independent programming validation, access controls, version locking, and
documented OQ/PQ or equivalent qualification.
