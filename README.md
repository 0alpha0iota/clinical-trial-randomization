# Industrial Clinical Trial Randomization Generator (SAS)

This repository now contains a production-oriented SAS randomization framework built from the original `main.sas` logic and output structure.

## Objectives

- Preserve core output fields and workflow style from the original program:
  - `Rand_ID`, `Rand_sub_ID`, `Group`, `Group_Num`, `block`, `size`
- Upgrade to enterprise-grade usage with:
  - modular macros
  - strong parameter assertions
  - controlled seed management (AUTO/FIXED)
  - run-level audit dataset

## Files

- `industrial_main.sas`  
  Main executable program; sets trial metadata and runs randomization macro.
- `macros/seed_utils.sas`  
  Seed generation and assertion utilities.
- `macros/randomization_engine.sas`  
  Core randomization engine.
- `main.sas`  
  Original program retained for reference.

## Supported randomization methods

- `SIMPLE`
- `BLOCKING`
- `STRATIFIED`

## Key industrial controls

1. **Input validation**
   - Validates method enumerations
   - Validates positive sample size and ratios
   - Validates consistency between names and ratio vectors

2. **Reproducibility**
   - Supports `seed_mode_plan=FIXED` and `seed_mode_strata=FIXED`
   - Captures seed and seed timestamp for audit

3. **Audit trail**
   - Writes run metadata and seed values to `randomization_audit_cohort<No>` dataset

4. **Output directory policy**
   - Dated output folder under `blind_code_test/<YYYY-MM-DD>/cohort_info`

## Execution

Run `industrial_main.sas` in SAS (SAS 9.4+ recommended).

## Regulatory / quality notes

This framework is designed to align with common CRO/sponsor expectations for non-adaptive, parallel-arm randomization operations:

- deterministic reproducibility when fixed seeds are used
- traceable audit metadata
- explicit parameter checks and fail-fast behavior

For strict production deployment in a validated environment, teams should additionally implement:

- independent programmer validation (double programming)
- SOP-governed release, code review, and version lock
- role-based output separation for blinded/unblinded listings
- formal OQ/PQ and change control records
