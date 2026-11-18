# SIMPLE Oxford

SIMPLE Oxford is the MATLAB/EEGLAB workflow used by the Oxford neonatal EEG
group. It prepares source recordings, runs SIMPLE (Single-event Measurement
Pipeline for EEG), and exports results for analysis. It supports several Oxford
datasets; the Petal trial is the example used in the SIMPLE methods paper.

**Software credits:** [Luke Baxter](https://github.com/lukebax), [Marianne van der Vaart](https://github.com/mvandervaart), and [Simon Marchant](https://github.com/simonmarchant) contributed equally to the development of this software.

Associated methods paper: citation and link to be added when available.

Petal dataset paper: Hauck et al. (2024), *Effect of parental touch on relieving
acute procedural pain in neonates and parental anxiety (Petal): a multicentre,
randomised controlled trial in the UK*, The Lancet Child & Adolescent Health 8,
259–269. <https://doi.org/10.1016/S2352-4642(23)00340-1>

## Start here

This repository contains the Oxford workflow and its functions. Run its scripts
from this checkout; a separate `simple` checkout is not required. Clinical EEG,
study spreadsheets, screening decisions, and saved results are not included.
To begin a study run, you need authorised access to its recordings and required
study spreadsheets.

- **New to SIMPLE?** Start with the [core guide](https://github.com/simple-eeg/simple#start-here).
- **Want a worked example without clinical data?** Use the [synthetic tutorial](https://github.com/simple-eeg/simple#synthetic-tutorial).
- **Working with Oxford data?** Follow [setup](#before-you-begin) and the [numbered workflow](#workflow).
- **Looking up formats or options?** Use the [technical reference](#technical-reference) and each function's MATLAB help.

The workflow reviews individual event–channel items: an EEG segment around an
event (an *epoch*) from one channel. Quality-control (QC) features describe
properties of these segments. Neurodynamic response functions (NRFs) are
waveform templates fitted to the EEG to quantify responses. Internal-reference
epochs provide nearby, non-target activity for comparison with the true event.

## Before you begin

### Software

The workflow requires MATLAB and EEGLAB, a MATLAB toolbox for EEG analysis.
The verified environment is MATLAB R2026a Update 4 with EEGLAB 2026.0.0.
Use MATLAB and EEGLAB versions supported on your operating system. The
project paths in the scripts are editable examples, not macOS requirements.
Required functionality includes:

- Statistics and Machine Learning Toolbox operations such as `corr`,
  `robustfit`, and `fitlm`;
- Econometrics Toolbox `fgls`;
- Signal Processing Toolbox operations used by filtering and spectral checks;
- Wavelet Toolbox for the time-frequency check; and
- the EEGLAB import support appropriate to the source format, such as Curry,
  XDF, or BIOSIG support.

CleanLine is optional. Preprocessing uses it when selected and otherwise uses
the configured notch-filter route.

### Data and script setup

For the Petal workflow, source preparation uses the EEG recordings and
`data_lists/medscinet_export_petal.xlsx`. Later publication-membership exports
also use `data_lists/medscinet_export_petal_pub.xlsx`. These private inputs must
be supplied locally; the code does not download them.

1. Make EEGLAB available on the MATLAB path. Set each script's editable
   checkout path, such as `baseDir`, `root`,
   `local_base`, or `PROJECT_ROOT`, to your local `simple-oxford` folder.
   Step 1.1 also requires the approved external source-folder path.
2. Set MATLAB's current folder to this checkout's `scripts/` folder. Open each
   numbered script in the MATLAB Editor and run the whole script.
3. Work in numerical order, checking the script's settings and inputs first.
   Pause for the manual checks described below rather than running all scripts
   as a batch.

The scripts use this checkout's functions and verify that the required helpers
resolve there. Scripts that need EEGLAB start it before adding those functions
to the MATLAB path. Do not add `NRFs/` to the path: templates are resolved
directly from this repository.

Review the settings for your dataset, including event mappings, channels,
sampling rates, filters, epoch and baseline windows, NRF profiles, screening,
exclusion handling, aggregation, and Step 9 exports. The checked-in options
include choices beyond the Petal analysis and are not automatically appropriate
for another dataset.

## Workflow

### Step 1 — Oxford source preparation

Step 1 inventories Oxford source material, combines study metadata, determines
the destination folders and filenames, and copies source files into local
`data/source/`. Review missing-file and naming information before continuing.

### Step 2 — Oxford raw-data preparation

Step 2 reads event annotations, applies the user-defined annotation mapping and
optional filtering or latency rules, converts supported formats to EEGLAB,
checks channels, and creates `data/raw/` and `data_lists/dataset_list.csv`.
This CSV is the dataset list, also called the *registry* in the code. Manual
checks include completing event `Type` mappings, selecting event filters,
marking latency corrections, and reviewing channel inventories.

After Step 2.9, choose whether to use the optional identifier-handling scripts:

| Choice | Scripts | What changes |
|---|---|---|
| Keep original identifiers | Skip Steps 2.10 and 2.11 | Continue with the dataset list and raw recordings from Step 2.9. |
| Replace identifiers | Run `step_2_raw_10_pseudonymise_ids.m` | Preserve the complete original raw folder as private `data/raw_orig/`; create a replacement-ID `data/raw/` and a private identity map. The copied `.set` files are byte-identical. |
| Also sanitise embedded metadata | Run Step 2.10, then `step_2_raw_11_sanitise_sets.m` | Remove or replace identifier- and path-bearing metadata inside the active pseudonymised `.set` files, preserving EEG signals and scientific metadata. `data/raw_orig/` is unchanged. |

Use these optional steps immediately after Step 2.9, before creating Step 3 or
later workflow state. Step 2.11 cannot run alone. Both scripts stop on invalid
state, support recovery after an interrupted operation, and work locally
without using the university server. See [identity details](#optional-identity-handling)
for exact formats and filesystem rules.

Keep `dataset_list.csv`, `data/raw_orig/`, and the unsanitised replacement-ID
`data/raw/` from Step 2.10 private. Even after Step 2.11, the recordings remain
pseudonymised research data subject to their existing access requirements.
The replacement-ID route is pseudonymisation, not anonymisation; it does not
make the data ready for public sharing.

### Steps 3–7 — SIMPLE framework

These implement the five software stages described in the
[core workflow reference](https://github.com/simple-eeg/simple#workflow-reference).
Their numbering differs from the core repository, and their grouping differs
from the five scientific steps in the methods paper.

| Oxford step | Core step | Stage |
|---|---|---|
| Step 3 | Step 1 | processing and epoching (`proc`) |
| Step 4 | Step 2 | QC and NRF quantification (`quant`) |
| Step 5 | Step 3 | individual summaries and pooling (`sum`) |
| Step 6 | Step 4 | manual epoch–channel screening (`screen`) |
| Step 7 | Step 5 | post-screening checks (`check`) |

Use the Oxford scripts in this checkout. The linked core guide explains stage
inputs, outputs, rationale, manual checkpoints, and operating rules.

Step 3 preprocesses continuous recordings, removes unwanted events, adds
configured offset or internal-reference events, and performs epoching and
baseline correction. Step 4 calculates per-event/channel QC features and NRF
fits. Step 5 creates individual and pooled summaries.

Step 6 creates a fixed screening package, records manual decisions, and applies
them to pooled outputs. Review each item using its waveform and QC evidence;
keep NRF magnitudes and downstream group or outcome information out of
screening decisions. True-event and internal-reference items receive separate
statuses. The Step 6.2 viewer's `File > Save PDF...` command exports the complete
current display, including the plots and Navigator, to a location you choose.
Saving this snapshot does not change the decisions.

Step 7 provides descriptive displays and machine-readable checks of the screened
results without changing screening decisions. The analysis unit remains one
event–channel item. Group-level inference requires one prespecified
participant-level contribution or an analysis that accounts for repeated
observations. Petal supplies one relevant record per participant.

### Step 8 — General manuscript outputs

The three Step 8 scripts write to `data/results/` and leave their MATLAB
figures, panel data, or tables available for inspection. Run them in numerical
order and stop if a script reports an error.

| Script | Purpose | Main inputs |
|---|---|---|
| `step_8_gen_1_check_plots.m` | Assemble Figure 3a's descriptive checks | screened pooled epochs, the saved Step 7.7 NRF result, and configured e-NRF/n-NRF 500-Hz templates |
| `step_8_gen_2_sample_details.m` | Summarise Petal participant characteristics | `dataset_list.csv` and `medscinet_export_petal.xlsx` |
| `step_8_gen_3_nrf_details.m` | Summarise and plot the NRF templates | the three configured 500-Hz templates |

**Step 8.1** writes `figure_3a_post_screening_descriptive_checks_petal.pdf`.
Its seven panels show recording-level time series, time-frequency displays, and
power spectral density (PSD), with `lance` true events on the left and
`lance_prestim` internal references on the right. The final row contains a
centred n-NRF comparison showing magnitudes and paired differences in µV.
It uses the saved paired Step 7.7 result without rerunning its bootstrap and
does not need the QC comparison result. It does not call a Step 7 script. The
figure, fixed configuration, calculated panel data, and graphics handles remain
in the MATLAB workspace.

**Step 8.2** writes the 15-row, two-column
`supplementary_table_1_petal_dataset_characteristics.csv`, the source for
Supplementary Table 3. It leaves `participantDetailsTable` and
`supplementaryTable1` in the workspace. If identifiers were replaced in Step 2,
it uses the private map to translate MedSciNet identities to replacement
`subjectID` values. The saved aggregate table contains no identifier and has
the same scientific values as the original-ID route.

**Step 8.3** writes
`supplementary_table_4_nrf_template_derivation_and_fitting_details.csv`
(nine rows, four columns) and
`supplementary_figure_1_nrf_template_visualisations.pdf` (three vector panels).
These supply Supplementary Table 6 and Supplementary Figure 13, respectively.
The figure plots stored NRF samples at their configured start times;
`supplementaryTable4` and the figure remain open for inspection.

Output filenames retain their original numbering. Manuscript tables use
selected source values with edited labels and formatting: Supplementary Table 6
has six rows and e-NRF, n-NRF, and p-NRF headings, whereas the nine-row source CSV
also retains derivation metadata. Both tables are written as
UTF-8 CSV files with a byte-order mark so en dashes and plus/minus symbols
display correctly in Excel. Their formatting is:

- participant table: en-dash subgroup labels rather than leading ASCII hyphen-minus; and
- NRF table: plain author-year Publication values without parentheses or asterisks.

Each script starts a fresh exact-name Command Window log before clearing the
Command Window, then validates inputs before creating the results directory or
writing scientific outputs. A rejected run can therefore replace the log without producing new
scientific output. A successful rerun replaces that script's log and outputs.

### Step 9 — Oxford JASP table preparation

These six scripts prepare CSV tables for analysis in JASP statistical software,
using screened EEG results and study metadata. The scripts run from
`step_9_jasp_1_data_prep_eeg_qc.m` through
`step_9_jasp_6_add_bvt_cols.m` and write to `data/results/`.

| Script | Purpose | Output | Expected Petal dimensions |
|---|---|---|---|
| 9.1 | Reshape screened QC features by participant | `jasp_data_eeg_qc.csv` | 104 rows × 19 columns |
| 9.2 | Reshape screened NRF features by participant | `jasp_data_eeg_nrf.csv` | 104 rows × 5 columns |
| 9.3 | Match and combine the QC and NRF tables | `jasp_data_eeg.csv` | 104 rows × 23 columns |
| 9.4 | Derive trial arm and heel-lance sleep state | `jasp_data_other.csv` | original IDs: 114 rows × 3 columns, including 10 metadata-only records; replacement IDs: the admitted 104 rows × 3 columns |
| 9.5 | Match study metadata to EEG participants | `jasp_data_all.csv` (provisional) | 104 rows × 25 columns |
| 9.6 | Add current-screening and publication-membership columns | `jasp_data_all.csv` (final) | 104 rows × 28 columns |

Run Steps 9.1–9.6 in order and stop on an error.
`jasp_data_all.csv` is provisional after Step 9.5 and complete after Step 9.6.
**Import it into JASP only after Step 9.6 succeeds.** If you rerun any Step 9
script, rerun every later-numbered Step 9 script through Step 9.6. Each script
replaces its CSV and log; an older output left after a failed run is not
evidence of success.

The files from Steps 9.1–9.4 remain as intermediates.
The five Step 9 `jasp_data_*.csv` files coexist with the
four Step 8 manuscript artifacts in `data/results/`; Step 9 does not replace
or remove the Step 8 files. Step 10 adds its PDF to the same directory without
replacing these outputs.

MedSciNet workbooks retain original private study IDs. When replacement IDs are
used, Steps 9.4 and 9.6 translate the original IDs through the private
`subjectID_orig`–`subjectID` map, and Step 9.5 checks that its intermediates use
the same identifier system. The final cohort remains 104 participants, with
unchanged scientific values. Identifier columns are read and checked as text,
so values such as `001`, `002`, and `010` retain their leading zeros in the final
CSV.

### Step 10 — Figure 4 assembly base

`step_10_gen_1_figure_4_base.m` creates a base for assembling manuscript Figure 4.
It requires the final Step 9.6 `data/results/jasp_data_all.csv` and the saved
`data/results/jasp_data_all.jasp` archive. Counts, trial arms, retained-set
membership, and nesting are checked from the CSV. Treatment estimates and
credible intervals are fixed display inputs transcribed from the accepted JASP
analysis. The script checks that the archive exists; it does not read its
results or rerun JASP.

MATLAB creates panels A–C. Panel B uses four equal-width bars to show retained
and excluded composition for the two retained-set definitions within each arm,
with counts as labels. Panels D and E are left blank for author-exported JASP
plots. The output, `data/results/figure_4_petal_applications_base.pdf`, is a
vector assembly base rather than the completed figure. Its log is
`data/logs/step_10_gen_1_figure_4_base.log`.

Source data, screening decisions, figures, and statistical interpretation
require human review. Successful scripts and regression tests establish
technical behaviour; they do not replace those scientific decisions.

## Technical reference

### Repository layout and logs

```text
simple-oxford/
├── data/                 local inputs, intermediate files, outputs, and logs
├── data_lists/           local dataset lists and study spreadsheets
├── functions/            MATLAB functions used by the workflow
├── NRFs/                 bundled NRF templates and nrf_config.ini
├── scripts/              numbered workflow scripts and the logging helper
├── tests/                synthetic regression fixtures and test runners
├── .gitignore
├── LICENSE
└── README.md
```

The tracked `.gitkeep` files create `data/` and `data_lists/` in a checkout. All
runtime contents of `data/`, and CSV/XLSX files anywhere beneath `data_lists/`,
are ignored by Git. Keep data files out of version control.

Scripts using the logging helper save the Command Window diary in `data/logs/`
and replace the existing log for that script.
All three Step 8 manuscript-output scripts, all six Step 9 scripts, and
Step 10.1 use logs named after their scripts. Logs are local
and ignored by Git.

### Dataset paths

Every registry path is validated before a governed write to processed datasets
or per-dataset summaries: the script checks each output destination before
saving. Dataset directories must be relative to this project
and stay within their stage's exact `data/raw`, `data/processed`, or
`data/summary` folder. Filenames must contain only the filename, without a path,
and end in lowercase `.set`. Processed datasets and all four per-dataset summary
outputs must have unique destinations.

The relevant step stops before writing the dataset list, processed datasets,
or per-dataset summaries if it finds an absolute path, traversal components
such as `..`, ambiguous separators, a path in a filename field, or a symbolic
link that resolves outside the permitted folder.

### Optional identity handling

Step 2.9 creates the five-column dataset list in this exact order:
`subjectID`, `sessionID`, `runID`, `path_raw`, and `EEGfile_raw`.
Step 2.10 expands it to this ten-column mapping:

```text
subjectID_orig, sessionID_orig, runID_orig, subjectID, sessionID,
runID, path_raw_orig, path_raw, EEGfile_raw_orig, EEGfile_raw
```

Replacement subject, session, and run labels preserve leading zeros and follow
the recording hierarchy. The new active `data/raw/` contains the admitted
recordings; `data/raw_orig/` preserves the complete original raw folder.

Both optional scripts allow ordinary, singly linked `.DS_Store` files in
`data/raw/` and `data/raw_orig/`. These macOS Finder files are neither deleted
nor treated as EEG inputs; active-folder checks and the `raw_orig` recovery
checksum ignore them. Symbolic links, hard links, special filesystem objects,
and directories named `.DS_Store` receive no exemption. All other unexplained
files and directories are rejected. The scripts' internal transaction folders
must contain exactly the expected files; unexpected contents stop the operation.

### Functions

The main entry points are:

- `preproc(EEG, options)` for rereferencing, resampling, filtering, line-noise
  handling, epoching, and baseline correction;
- `add_offset_events` for adding events at a specified offset from source events;
- `quality_control_features` and its 11 `calc_*` feature calculators;
- `estimate_response(EEG, options)` and `jittercorrect` for NRF estimation;
- `NRFUtils` for configuration, mapping, template resolution, and fit caching;
- `validate_dataset_registry_paths` for checking dataset and output paths;
- Curry/XDF conversion and event-reading functions;
- time-series averaging, NRF-overlay, and paired-effect helpers; and
- diagnostics, plotting, and save helpers used by the numbered scripts.

`preproc` does not create offset events. Step 3 first preprocesses the continuous
recording, calls `add_offset_events` with the configured source-event,
annotation, and out-of-bounds policy, then calls `preproc` again for epoching
and baseline correction.

### NRF templates and configuration

The three bundled templates represent the early sensory response (e-NRF),
later noxious-evoked response (n-NRF), and preterm noxious response (p-NRF).
Their filenames in `NRFs/` are:

```text
early_NRF_500Hz.mat
noxious_NRF_500Hz.mat
noxious_preterm_NRF_500Hz.mat
```

Each MAT file stores a real double column vector `NRF` and scalar `fs = 500`.
Each stored NRF has mean zero and discrete L2 norm one within floating-point
precision. The dimensionless template gives its signed fitted coefficient
the EEG input's unit; that coefficient is not a peak EEG amplitude. Template
and EEG sampling rates must match exactly; the estimator does not resample
templates.

`NRFs/nrf_config.ini` defines the profiles used in Step 4. A profile contains
exactly six settings: `NRFName`, `baselineLength`, `jitter`, `channel`,
`projectionTimes_pre`, and `projectionTimes_post`. `NRFName` is the template's
basename, which resolves to the matching file in this repository's `NRFs/`
folder.

Supply exactly one projection start per fit:

- `projectionTimes_pre`: one finite scalar at or before 0 ms, with the post value empty; or
- `projectionTimes_post`: one finite scalar at or after 0 ms, with the pre value empty.

Vectors, two starts, no start, nonfinite values, and wrong-sign starts are
rejected before computation. The public estimator defaults to an empty pre
start and a post start of 400 ms. Estimator and plotting calls can also use an
explicit MAT-file path. Outputs retain the validated basename as the NRF
identity and record the canonical file path for provenance.

## Tests

`tests/run_all_tests.m` uses synthetic EEG fixtures; it does not read project
datasets or run numbered scripts against project data. It requires the exact
verified versions: MATLAB R2026a Update 4 and EEGLAB 2026.0.0. Use a dedicated
MATLAB session because some tests run temporary scripts that clear the base
workspace.

Replace the example paths below with your checkout and EEGLAB locations:

```matlab
oxfordRoot = '/path/to/simple-oxford';
eeglabRoot = '/path/to/eeglab';
addpath(fullfile(oxfordRoot, 'tests'), '-begin');
results = run_all_tests(oxfordRoot, eeglabRoot);
assert(results.passed);
```

The suite checks preprocessing, response estimation, jitter correction, QC,
all three templates, MATLAB path precedence, repository-local template use,
dataset paths, effective processing state, optional Step 2 identity handling
and `.set` sanitisation, NRF result replacement, and public APIs. Temporary
copies of the Step 8 and Step 9 scripts check all four manuscript outputs
(including both PDFs) and the five CSVs produced by the complete six-script
heel-lance export chain.

The GitHub workflow checks Python source contracts on macOS, Windows, and
Linux. On Windows it also checks file-link inspection under an ordinary user
account. These checks do not run MATLAB or replace the synthetic MATLAB suite.

Run static repository checks from the checkout root:

```sh
./tests/run_static_checks.sh
```

## Licence

The software, configuration files, test scripts, and associated documentation
are licensed under [Apache License 2.0](LICENSE).

The three NRF template MAT files and the numerical test data in
[`tests/fixtures/simple_scientific_oracle_v1.mat`](tests/fixtures/simple_scientific_oracle_v1.mat)
are licensed under **CC BY 4.0**. See the
[NRF data licence and source studies](NRFs/README.md).
