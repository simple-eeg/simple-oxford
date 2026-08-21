# SIMPLE Oxford

SIMPLE Oxford is the MATLAB/EEGLAB workflow used by the Oxford neonatal EEG
group. It covers Oxford-specific source preparation, the complete SIMPLE EEG
workflow, and analysis-specific export. The repository supports multiple Oxford
datasets; the Petal trial is the instantiation used in the SIMPLE methods paper,
not the limit of the codebase.

Associated methods paper: citation and link to be added when available.

Petal dataset paper: Hauck et al. (2024), *Effect of parental touch on relieving
acute procedural pain in neonates and parental anxiety (Petal): a multicentre,
randomised controlled trial in the UK*, The Lancet Child & Adolescent Health 8,
259–269. <https://doi.org/10.1016/S2352-4642(23)00340-1>

## Repository layout

```text
simple-oxford/
├── data/                 local inputs, intermediate files, outputs and logs
├── data_lists/           local dataset lists and study spreadsheets
├── functions/            MATLAB functions used by the workflow
├── NRFs/                 bundled NRF templates and nrf_config.ini
├── scripts/              numbered workflow scripts and the logging helper
├── tests/                synthetic regression fixtures and test runners
├── .gitignore
├── LICENSE
└── README.md
```

`data/` and `data_lists/` are present in a checkout through tracked `.gitkeep`
files. Every runtime descendant of `data/` is local and ignored by Git. CSV and
XLSX files anywhere beneath `data_lists/` are also ignored. Do not put data
files in version control.

Scripts that call the logging helper write their Command Window diary to
`data/logs/`. A run replaces the existing log for that script, and all logs
are ignored by Git. All three Step 8 manuscript-output scripts and all six
Step 9 JASP-preparation scripts create exact-name logs.

## Software and setup

The workflow requires MATLAB and EEGLAB. The verified environment is
MATLAB R2026a Update 4 with EEGLAB 2026.0.0. Required functionality includes:

- Statistics and Machine Learning Toolbox operations such as `corr`,
  `robustfit` and `fitlm`;
- Econometrics Toolbox `fgls`;
- Signal Processing Toolbox operations used by filtering and spectral checks;
- Wavelet Toolbox for the time-frequency check; and
- the EEGLAB import support appropriate to the source format, such as Curry,
  XDF or BIOSIG support.

CleanLine is optional. Preprocessing uses it when selected and otherwise uses
the configured notch-filter route.

Scripts that call repository functions start EEGLAB, prepend this checkout's
`functions/` directory to the MATLAB path, and verify that required functions
resolve there. Do not add `NRFs/` to the MATLAB path; logical template names
are resolved directly against this repository.

Every registry path is validated before a governed write. Dataset directories
must be project-relative descendants of the exact `data/raw`,
`data/processed` or `data/summary` root for their stage; dataset filenames must
be basenames with the exact lowercase `.set` extension; and processed and all
four per-dataset summary output targets must be unique. Absolute, traversing,
separator-ambiguous or path-like targets and symlink-based canonical escapes stop the script
before any registry, processed-dataset or summary-output write begins.

Most scripts contain an editable Oxford root variable such as `baseDir`,
`root`, `local_base` or `PROJECT_ROOT`. Set that declaration to the location of
your checkout before running the script. Run numbered scripts from the
`scripts/` folder using ordinary MATLAB script semantics. The workflow is
staged and includes deliberate manual inspection points; it is not a single
batch command.

## Functions

The repository contains the functions used by the Oxford workflow. Important
public entry points include:

- `preproc(EEG, options)` for rereferencing, resampling, filtering, line-noise
  handling, epoching and baseline correction;
- `add_offset_events` for the separate, explicit offset-event mechanism;
- `quality_control_features` and its 11 `calc_*` feature calculators;
- `estimate_response(EEG, options)` and `jittercorrect` for NRF estimation;
- `NRFUtils` for configuration, mapping, template resolution and fit caching;
- `validate_dataset_registry_paths` for fail-closed dataset and output paths;
- Curry/XDF conversion and event-reading functions;
- time-series averaging, NRF-overlay and paired-effect helpers; and
- diagnostics, plotting and save helpers used by the numbered scripts.

`preproc` intentionally does not create offset events. Step 3 first performs
continuous preprocessing, then calls `add_offset_events` under the configured
source-event, annotation and out-of-bounds policy, and finally calls `preproc`
again for epoching and baseline correction.

## NRF templates and configuration

`NRFs/` contains six tracked templates:

```text
early_NRF_500Hz.mat
early_NRF_2000Hz.mat
noxious_NRF_500Hz.mat
noxious_NRF_2000Hz.mat
noxious_preterm_NRF_500Hz.mat
noxious_preterm_NRF_2000Hz.mat
```

Every template MAT file contains `NRF` and `fs`. The template sampling rate
must exactly equal the EEG sampling rate; the estimator does not resample
templates.

`NRFs/nrf_config.ini` defines the profiles used by Step 4 NRF feature
extraction. Each profile has exactly six settings: `NRFName`,
`baselineLength`, `jitter`, `channel`, `projectionTimes_pre` and
`projectionTimes_post`. `NRFName` is a logical basename that resolves to the
matching file in this repository's `NRFs/` directory.

Exactly one projection start must be supplied per fit:

- `projectionTimes_pre` may be one finite scalar at or before 0 ms while the
  post value is empty; or
- `projectionTimes_post` may be one finite scalar at or after 0 ms while the
  pre value is empty.

Vectors, two starts, no start, nonfinite values and wrong-sign starts are
rejected before computation. The public estimator defaults to an empty pre
start and a post start of 400 ms. Estimator and plotting calls may also use an
explicit MAT-file path; outputs retain the validated logical basename as the
NRF identity and record the canonical file used as provenance.

## Workflow

Run scripts in numerical order, checking each script's user-editable settings
and expected inputs before execution.

### Step 1 — Oxford source preparation

Inventories Oxford source material, combines study metadata, derives the
destination structure and copies source files into the local `data/source/`
layer. Review missing-file and naming information before continuing.

### Step 2 — Oxford raw-data preparation

Reads event annotations, applies the author-defined annotation mapping and
optional filtering or latency rules, converts supported source formats to
EEGLAB, checks channels, and creates `data/raw/` plus the final
`data_lists/dataset_list.csv`.

Step 2.9 creates the ordinary five-column registry in this exact order:
`subjectID`, `sessionID`, `runID`, `path_raw`, and `EEGfile_raw`. Two final
Step 2 scripts are optional:

- `step_2_raw_10_pseudonymise_ids.m` preserves the complete original raw tree
  as private `data/raw_orig/`, builds a new active `data/raw/` containing the
  admitted recordings under replacement subject/session/run labels, and
  expands the private registry to the exact mapped core
  `subjectID_orig`, `sessionID_orig`, `runID_orig`, `subjectID`, `sessionID`,
  `runID`, `path_raw_orig`, `path_raw`, `EEGfile_raw_orig`, `EEGfile_raw`.
  Replacement labels preserve leading zeros and follow the recording
  hierarchy. The copied `.set` bytes are not altered by this script.
- `step_2_raw_11_sanitise_sets.m` may run only after Step 2.10. It sanitises
  identifier- and path-bearing metadata inside the active pseudonymised
  `.set` files while preserving the EEG signals and scientific metadata. It
  never changes `data/raw_orig/`.

Both transactions tolerate ordinary, singly linked `.DS_Store` files as
volatile macOS Finder metadata in `data/raw/` and `data/raw_orig/`. They do not
delete these files or treat them as EEG inputs; active-tree checks and the
`raw_orig` recovery digest ignore them. Links, hard links, and special objects
bearing that name remain unsafe; a directory bearing it receives no exemption.
Every other unexplained file or directory remains rejected, and the internal
transaction workspaces remain exact and fail-closed.

The supported routes are therefore: skip both scripts; run Step 2.10 only; or
run Step 2.10 followed by Step 2.11. Running Step 2.11 without Step 2.10 is
rejected. Both scripts are fail-closed transactions with restart recovery;
they run only immediately after Step 2.9 and before material Step 3-or-later
state, and they do not use the university server. `dataset_list.csv`,
`data/raw_orig/`, and an unsanitised Step-2.10-only `data/raw/` remain private
linkage material. Even sanitised replacement SETs remain governed,
pseudonymised research data and are not automatically suitable for sharing.
The replacement-ID route is pseudonymisation, not anonymisation.

Manual work can include completing event `Type` mappings, selecting event
filters, marking latency corrections and reviewing channel inventories.

### Steps 3–7 — SIMPLE framework

The middle block implements the five stages documented in `simple`:

| Oxford step | Framework step | Stage |
|---|---|---|
| Step 3 | Step 1 | processing and epoching (`proc`) |
| Step 4 | Step 2 | QC and NRF quantification (`quant`) |
| Step 5 | Step 3 | individual summaries and pooling (`sum`) |
| Step 6 | Step 4 | manual epoch-channel screening (`screen`) |
| Step 7 | Step 5 | post-screening checks (`check`) |

These scripts run from this repository. See the `simple` README for
detailed stage inputs, outputs, rationale, manual checkpoints and operating
rules.

Step 3 preprocesses continuous recordings, removes unwanted events, adds
configured offset or internal-reference events, and performs epoching and
baseline correction. Step 4 calculates per-event/channel QC features and NRF
fits. Step 5 creates individual and pooled summaries. Step 6 creates the fixed
screening package, records manual decisions and applies them to pooled outputs.
Step 7 provides display and machine-readable checks of the screened results.

### Step 8 — General manuscript outputs

The three Step 8 scripts create manuscript-ready figures and tables under
`data/results/` while retaining the corresponding MATLAB figures, panel data
or tables for inspection. They are `step_8_gen_1_check_plots.m`,
`step_8_gen_2_sample_details.m` and `step_8_gen_3_nrf_details.m`.

| Script | Responsibility | Inputs | Outputs | Expected current Petal result |
|---|---|---|---|---|
| 8.1 | Assemble the fixed post-core guardrail checks for Figure 3 | screened pooled epochs, the saved Step 7.6/7.7 separation results and the configured early/later noxious 500-Hz NRF templates | `figure_3_post_core_guardrails_in_the_petal_dataset.pdf` | four rows by two columns: time series, time-frequency, PSD, QC separation and NRF separation panels |
| 8.2 | Create Petal participant characteristics | `dataset_list.csv` and `medscinet_export_petal.xlsx` | `supplementary_table_1_petal_dataset_characteristics.csv` | 15 rows x 2 columns; Supplementary Table 1 |
| 8.3 | Summarise and visualise the three NRF templates | the three configured 500-Hz NRF templates | `supplementary_table_4_nrf_template_derivation_and_fitting_details.csv` and `supplementary_figure_1_nrf_template_visualisations.pdf` | 9 rows x 4 columns and a three-panel vector PDF; Supplementary Table 4 and Supplementary Figure 1 |

Run Steps 8.1, 8.2 and 8.3 in numeric order and stop if any script reports an
error. Each script starts a fresh exact-name Command Window log before clearing the
Command Window, then validates its required inputs before creating the results
directory or writing its own scientific targets. A rejected run may therefore
create or replace only that script's log; it does not create a scientific
output. A successful rerun replaces its exact log and scientific targets. Step
8.1 leaves its eight-panel figure, fixed configuration, calculated panel data
and graphics handles in the workspace for inspection. It calculates both
`lance_prestim` and `lance` time-series, time-frequency and PSD panels at the
recording level, then plots the already-saved paired Step 7.6/7.7 QC and NRF
results without rerunning their bootstrap. It does not call a Step 7 script.
Step 8.2 leaves `participantDetailsTable` and `supplementaryTable1` in the
workspace. In the optional mapped route it uses the private registry only to
translate the MedSciNet source identity to replacement `subjectID`; the saved
aggregate table contains no identifier and is scientifically unchanged. Step
8.3 leaves `supplementaryTable4` and its figure open for inspection.

Both Step 8 tables are written as UTF-8 CSV files with a byte-order mark so
their en dashes and plus/minus symbols display correctly when the files are
opened directly in Microsoft Excel. Their presentation contracts are:

- Supplementary Table 1: en-dash subgroup labels rather than leading ASCII hyphen-minus;
- Supplementary Table 4: plain author-year Publication values without parentheses or asterisks.

### Step 9 — Oxford JASP table preparation

The six Step 9 scripts prepare, combine and annotate Oxford-specific CSV
tables for later analysis in JASP. They use the screened EEG results and study
metadata and write under `data/results/`. They are numbered
`step_9_jasp_1_data_prep_eeg_qc.m` through
`step_9_jasp_6_add_bvt_cols.m`.

| Script | Responsibility | Output | Expected current Petal result |
|---|---|---|---|
| 9.1 | Reshape screened QC features by participant | `jasp_data_eeg_qc.csv` | 104 rows x 19 columns; intermediate |
| 9.2 | Reshape screened NRF features by participant | `jasp_data_eeg_nrf.csv` | 104 rows x 5 columns; intermediate |
| 9.3 | Match and combine the QC and NRF tables | `jasp_data_eeg.csv` | 104 rows x 23 columns; intermediate |
| 9.4 | Derive trial arm and heel-lance sleep state | `jasp_data_other.csv` | original route: 114 rows x 3 columns, including 10 metadata-only records; mapped route: the admitted 104 rows x 3 columns |
| 9.5 | Match study metadata to the EEG participants | `jasp_data_all.csv` | 104 rows x 25 columns; provisional |
| 9.6 | Add current-screening and publication-membership columns | `jasp_data_all.csv` | 104 rows x 28 columns; final JASP endpoint |

Run Steps 9.1--9.6 in numeric order and stop if any script reports an error.
The files from Steps 9.1--9.4 are retained intermediates.
`jasp_data_all.csv` is provisional after Step 9.5 and becomes complete only
after Step 9.6 succeeds. If any Step 9 script is rerun, rerun every
later-numbered Step 9 script through Step 9.6 before importing the final file
into JASP. Each script replaces its CSV target and exact-name Command Window
log, so the presence of an older output does not establish that a failed
rerun succeeded. The five Step 9 `jasp_data_*.csv` files coexist with the
four Step 8 manuscript artifacts in `data/results/`; Step 9 does not remove
or replace the Step 8 files.

The external MedSciNet workbooks always retain their original private study
IDs. In the optional mapped route, Steps 9.4 and 9.6 translate those IDs through
the private `subjectID_orig` to `subjectID` registry map before matching; Step
9.5 validates that its intermediates use one consistent namespace. The final
104-participant cohort and all scientific values are unchanged. All MATLAB
imports and output checks keep identifier columns as text, so replacement IDs
such as `001`, `002`, and `010` retain their leading zeros through the final
Step 9 CSV.

## User decisions and scientific boundaries

The codebase exposes settings beyond the Petal paper route. Review enabled and
disabled user options rather than assuming the checked-in settings are
appropriate for another dataset. In particular, confirm event mappings,
channels, sampling rates, filters, epoch and baseline windows, NRF profiles,
screening settings, exclusion handling, aggregation choices and Step 9 export
selections.

The core processing unit is one analysed event-channel instance. Group-level
inference requires one prespecified participant-level contribution or an
analysis that accounts for repeated observations. Petal supplies one relevant
record per participant.

Source data, manual screening, figures and final statistical interpretation
remain human-reviewed scientific inputs. A successful script or regression
test establishes technical behaviour; it does not replace those decisions.

## Tests

`tests/run_all_tests.m` uses synthetic EEG fixtures only. It exercises the
preprocessing, response, jitter and QC contracts, all six bundled templates,
path precedence, local template binding, registry paths, effective processing
state, the optional Step 2 identity and `.set`-sanitisation transactions, NRF
state replacement, all three Step 8 manuscript-output scripts, the
complete pain-only Step 9 six-script CSV chain
and the public APIs in the verified MATLAB/EEGLAB environment. The Step 8 and
Step 9 tests run temporary
copies of the relevant scripts against synthetic fixtures. They verify the
four Step 8 manuscript artifacts, including both PDF contracts, and the
five Step 9 JASP CSV artifacts. The suite does not read project datasets or
run a numbered script against project data.
Run it in a dedicated MATLAB session because the temporary script-interface
fixtures intentionally use ordinary script/base-workspace semantics and clear
that base workspace.

From MATLAB, call the runner with explicit roots:

```matlab
addpath(fullfile(oxfordRoot, 'tests'), '-begin');
results = run_all_tests(oxfordRoot, eeglabRoot);
assert(results.passed);
```

The static repository checks can be run from the checkout root:

```sh
./tests/run_static_checks.sh
```

## License

This repository is licensed under the Apache License 2.0. See `LICENSE`.
