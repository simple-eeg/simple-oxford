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

Each numbered script writes its Command Window diary to `data/logs/`. A run
replaces the existing log for that script, and all logs are ignored by Git.

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

### Step 8 — Oxford analysis export

Builds Oxford-specific JASP-ready tables from the screened EEG results and
study metadata, with bounded descriptive and figure scripts used for the
methods-paper analysis. The combined endpoint is the subject-level
`data/jasp/jasp_data_all.csv` when that route is configured and run.

## User decisions and scientific boundaries

The codebase exposes settings beyond the Petal paper route. Review enabled and
disabled user options rather than assuming the checked-in settings are
appropriate for another dataset. In particular, confirm event mappings,
channels, sampling rates, filters, epoch and baseline windows, NRF profiles,
screening settings, exclusion handling, aggregation choices and Step 8
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
state, NRF state replacement and the public APIs in the verified MATLAB/EEGLAB
environment. It does not read project datasets or run a numbered workflow
script.

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
