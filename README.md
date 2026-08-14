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
├── tests/                synthetic regression fixtures and test runner
├── LICENSE
└── README.md
```

`data/` and `data_lists/` are deliberately present in a fresh clone through
tracked `.gitkeep` files. Every runtime descendant of `data/` is local and
ignored by Git. CSV and XLSX files anywhere beneath `data_lists/` are also
ignored. Do not put data files in version control.

Each numbered script writes its Command Window diary to `data/logs/`. Logs are
replaced on a new run of the same script and are ignored by Git. A root-level
`logs/` directory is not part of the supported layout.

## Software and setup

The workflow requires MATLAB and EEGLAB. The currently verified environment is
MATLAB R2026a Update 4 with EEGLAB 2026.0.0. Required MATLAB functionality
includes Statistics and Machine Learning Toolbox operations such as `corr`,
`robustfit` and `fitlm`, Econometrics Toolbox `fgls`, Signal Processing Toolbox
operations used by filtering and spectral checks, and Wavelet Toolbox for the
time-frequency check. Individual routes may also require the EEGLAB import
support appropriate to their source format, such as Curry, XDF or BIOSIG
support. CleanLine is optional: preprocessing can use it when selected and
otherwise uses the retained notch-filter route.

No separate SIMPLE EEGLAB plugin is required. The scripts add this repository's
`functions/` directory after starting EEGLAB, put it at path precedence, and
verify that required functions resolve to this checkout. Do not add `NRFs/` to
the MATLAB path; logical template names are resolved directly against this
repository.

Most scripts contain an editable Oxford root variable such as `baseDir`,
`root`, `local_base` or `PROJECT_ROOT`. Set that declaration to the location of
your checkout before running the script. Run numbered scripts from the
`scripts/` folder using ordinary MATLAB script semantics. The workflow is
staged and includes deliberate manual inspection points; it is not one
push-button batch command.

## Bundled functions

The repository contains the complete functions needed for the Oxford SIMPLE
workflow. Important public entry points include:

- `preproc(EEG, options)` for rereferencing, resampling, filtering, line-noise
  handling, epoching and baseline correction;
- `add_offset_events` for the separate, explicit offset-event mechanism;
- `quality_control_features` and its 11 `calc_*` feature calculators;
- `estimate_response(EEG, options)` and `jittercorrect` for NRF estimation;
- `NRFUtils` for configuration, mapping, template resolution and fit caching;
- Curry/XDF conversion and event-reading functions;
- time-series averaging, NRF-overlay and paired-effect helpers; and
- diagnostics, plotting and save helpers used by the numbered scripts.

`preproc` intentionally does not create offset events. Step 3 first performs
continuous preprocessing, then calls `add_offset_events` under the configured
source-event, annotation and out-of-bounds policy, and finally calls `preproc`
again for epoching and baseline correction.

## NRF templates and configuration

`NRFs/` contains six bundled, tracked templates:

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
`projectionTimes_post`. `NRFName` in the INI is a logical basename and always
binds to the matching file in this repository's `NRFs/` directory.

Exactly one projection start must be supplied per fit:

- `projectionTimes_pre` may be one finite scalar at or before 0 ms while the
  post value is empty; or
- `projectionTimes_post` may be one finite scalar at or after 0 ms while the
  pre value is empty.

Vectors, two starts, no start, nonfinite values and wrong-sign starts are
rejected before computation. The public estimator's clean default is an empty
pre start and a post start of 400 ms. Public estimator and plotting calls may
also use an explicit MAT-file path; outputs keep the validated logical basename
as their NRF identity while recording the canonical file used as provenance.

## Workflow

Run scripts in numerical order, checking each script's user-editable settings
and expected inputs before execution.

### Step 1 — source preparation

Inventories the Oxford source material, combines study metadata, derives the
renamed destination structure and copies source files into the local
`data/source/` layer. Review missing-file and naming information before moving
on.

### Step 2 — raw-data preparation

Reads event annotations, applies the author-defined annotation mapping and
optional filtering/latency rules, converts supported source formats to EEGLAB,
checks channels, and creates the framework-ready `data/raw/` layer and final
`data_lists/dataset_list.csv`.

Manual work can include populating event `Type` mappings, selecting event
filters, marking latency corrections and reviewing channel inventories.

### Step 3 — processing

Loads raw EEGLAB datasets, performs the configured preprocessing, removes
unwanted events, optionally adds explicit offset/reference events, epochs and
baseline-corrects, and saves processed datasets with structured provenance.

### Step 4 — quantification

Calculates the selected per-event/channel QC features, constructs epoch
indices, and estimates configured NRF features. NRF fits are cached per
profile/channel while retaining event-level outputs.

### Step 5 — summarisation and pooling

Adds output paths, produces individual QC/NRF/epoch summaries, pools them, and
provides plots for inspection. Plot overlays can be disabled; when enabled,
templates are resolved through the same local-or-explicit contract as the
estimator.

### Step 6 — manual screening

Creates a versioned screening package, opens the manual viewer and applies the
saved decisions to pooled outputs. Do not treat the mutable decision snapshot
as an action history. Complete the intended manual inspection before applying
decisions.

### Step 7 — post-screening checks

Inspects included epochs, average time series, time-frequency and spectral
summaries, and paired QC/NRF separation checks. Several scripts display figures
for scientific review rather than producing an automatic acceptance decision.

### Step 8 — analysis export

Builds Oxford-specific JASP-ready tables from the screened EEG results and
study metadata, and includes bounded descriptive/figure scripts used for the
methods-paper analysis. The combined endpoint is the subject-level
`data/jasp/jasp_data_all.csv` when that route is configured and run.

## User decisions and scientific boundaries

The codebase exposes settings beyond the Petal paper route. Review all enabled
and disabled user options rather than assuming the checked-in defaults are
appropriate for another dataset. In particular, confirm event mappings,
channels, sampling rates, filters, epoch windows, baseline windows, NRF
profiles, screening settings, exclusion handling, aggregation choices and
analysis-specific Step 8 selections.

Source data, manual screening, figures and final statistical interpretation
remain human-reviewed scientific inputs. A successful script or regression
test establishes technical behaviour; it does not replace those decisions.

## Tests

`tests/run_all_tests.m` uses synthetic EEG fixtures only. It exercises the
absorbed preprocessing, response, jitter and QC contracts, all six bundled
templates, path precedence, local template binding and clean public APIs in the
locked MATLAB/EEGLAB environment. It does not read project datasets or run a
numbered workflow script.

From MATLAB, call the runner with explicit roots:

```matlab
addpath(fullfile(oxfordRoot, 'tests'), '-begin');
results = run_all_tests(oxfordRoot, eeglabRoot);
assert(results.passed);
```

The repository is licensed under Apache License 2.0; see `LICENSE`.
