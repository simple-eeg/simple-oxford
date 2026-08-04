# simple-oxford

A MATLAB workflow for taking the Oxford EEG dataset from source-file preparation through framework instantiation to a final JASP-ready analysis table.

**Associated methods paper:** [Add citation and link here when available]

**Associated dataset paper:** 
*Effect of parental touch on relieving acute procedural pain in neonates and parental anxiety (Petal): a multicentre, randomised controlled trial in the UK.* Hauck et al., 2024. The Lancet Child & Adolescent Health 8, 259–269. https://doi.org/10.1016/S2352-4642(23)00340-1


## Repository overview

This repository is the full Oxford analysis pipeline used for the methods paper. It begins with the Oxford dataset in the source-file formats and storage structure used by the research group, prepares those data for analysis, instantiates the EEG framework workflow on the prepared datasets, and then reshapes selected outputs into a final subject-level table for downstream statistical analysis in JASP.

The repository therefore has three practical parts:

1. **Oxford-specific preparation before the framework**
2. **Framework instantiation on the Oxford dataset**
3. **Oxford-specific export after the framework**

In this repository, the Oxford dataset is the **Petal trial dataset**. The practical role of this repository is to take that dataset from its original storage and file formats to the final tabular outputs used in the Oxford analyses for the methods paper.

## What this repository is for

This repository is for:

- preparing the Oxford/Petal EEG dataset for analysis
- converting Oxford source files into framework-ready EEGLAB datasets
- instantiating the framework workflow on the Oxford dataset
- producing screened EEG-derived outputs for the Oxford analyses
- exporting a final subject-level CSV for downstream statistical analysis in JASP

## What this repository is not for

This repository is not intended to be:

- a general-purpose EEG toolbox
- the primary place to learn the framework internals in detail
- a one-click workflow with no user judgement or inspection points
- a generic clinical-trial analysis repository independent of the Oxford dataset

## Relationship to the methods paper

This repository produces the Oxford dataset outputs used in the methods paper. It is practical and pipeline-facing rather than manuscript-facing. The repository is intended to stand on its own as documentation of the Oxford workflow, while the associated methods paper provides the broader methodological framing and analysis context.

## Relationship to the other repositories

### How `simple-oxford` relates to `simple-framework`

`simple-framework` is the standalone implementation of the framework workflow. In `simple-oxford`, that framework appears as the middle block of the repository.

Steps 3–7 in `simple-oxford` correspond to the workflow documented in `simple-framework`:

- Step 3 = processing
- Step 4 = quantification
- Step 5 = summarisation and pooling
- Step 6 = screening
- Step 7 = post-screening checks

### How `simple-oxford` differs from `simple-framework`

`simple-oxford` is broader in scope than `simple-framework`.

Whereas `simple-framework` begins from already prepared EEGLAB raw data and an appropriate `dataset_list.csv`, `simple-oxford` includes:

- Oxford-specific source preparation before the framework begins
- Oxford-specific raw-data preparation before the framework begins
- Oxford-specific JASP export after the framework ends

So `simple-framework` is the clearer standalone representation of the framework itself, whereas `simple-oxford` is the full Oxford beginning-to-end pipeline that contains that framework inside it.

## How to approach this repository

This repository is best understood as a **staged workflow with explicit user intervention points**, not as a single push-button script sequence.

In broad terms, the flow is:

1. prepare and rename the Oxford source files
2. convert them into framework-ready EEGLAB raw datasets
3. run the framework workflow on those prepared datasets
4. export selected screened outputs into a final JASP-ready analysis table

Before running the scripts, read:

- **Before you begin**
- **Workflow stages in this repository**
- **Points where user input or inspection is required**
- **Steps 3–7: framework instantiation**

The middle framework block is intentionally not re-documented in full here. This README explains what that block does within `simple-oxford`, while the detailed documentation of those steps is provided in the `simple-framework` repository README.

## Repository structure

Data, logs, generated outputs, screening decisions, and downstream analysis files are local working materials excluded from version control; a fresh clone contains the workflow code, tracked configuration, and documentation only.

### `data_lists/`

Core metadata and study-specific inputs used by the pipeline.

Key files include:

- `medscinet_export_petal.xlsx`
- `medscinet_export_petal_pub.xlsx`
- `dataset_list_prelim.xlsx`
- `dataset_list.csv`

### `functions/`

MATLAB helper functions used by the runnable scripts.

This folder supports:

- source-file event reading
- source-to-EEGLAB conversion
- and other script-level helper operations

### `scripts/`

Runnable MATLAB scripts organised into the repository workflow steps.

This folder also contains `log_command_window.m`, which is used to write per-script Command Window log files.

### `data/source/`

This is the local renamed source-data layer created from the original Oxford storage setup.

It is an intermediate working layer, not the final raw input to the framework steps.

### `data/raw/`

This is the EEGLAB `.set` layer created from `data/source/`.

It is the raw input layer handed forward into the framework-instantiating steps.

### `data/processed/`, `data/summary/`, and screening outputs

These folders are produced by the framework block in Steps 3–7 and contain:

- processed epoched datasets
- per-dataset and pooled summary outputs
- screening packages and decisions
- screened pooled outputs
- post-screening outputs

### `data/jasp/`

This folder contains the subject-level export tables created in Step 8.

It includes the final JASP-ready outputs for the Oxford analyses.

### `logs/`

Per-script Command Window logs written by `log_command_window.m`.

## Before you begin

### Software requirements

This repository assumes access to:

- **MATLAB**
- **EEGLAB**
- the **SIMPLE** EEGLAB plugin
- the MATLAB toolboxes required by the specific functions you use

### Expected source-data location and naming

The earliest input to this repository is not an EEGLAB raw `.set` layer. Instead, the workflow begins from the Oxford source files in the storage layout and file formats used by the research group.

During Steps 1–2, those files are copied, renamed, organised into a local BIDS-style structure, and converted into EEGLAB `.set` files.

By the time the framework block begins, raw datasets are expected under `data/raw/` using a BIDS-style folder and filename convention based on subject, session, and run identifiers.

Example:

```text
data/raw/sub-Ox60001/ses-01/eeg/sub-Ox60001_ses-01_run-01_eeg.set
```

Here:

- `Ox60001` is the subject ID
- `01` is the session ID
- `01` is the run ID

### Path editing

The scripts currently use project paths such as `baseDir` or `root` defined within the scripts themselves. You should review and edit these paths to match your local setup before running the workflow.

### Running scripts from the `scripts` folder

It is recommended to run the workflow from within the `scripts` folder, or otherwise ensure that `scripts/` is on the MATLAB path.

This matters because the helper `log_command_window.m` lives in `scripts/` and is called at the start and end of the runnable scripts.

### Logging

Each runnable script starts and stops Command Window logging via `log_command_window('start')` and `log_command_window('stop')`.

This creates a per-script log file in `logs/`, which is useful for:

- reviewing warnings and errors later
- checking what happened during a run
- preserving an audit trail of script output

## High-level workflow overview

At a high level, this repository does four things:

1. prepares the Oxford source files in a standard local structure
2. converts them into raw EEGLAB datasets suitable for the framework
3. runs the framework workflow on those prepared datasets
4. exports selected screened outputs into a final JASP-ready table

## Workflow stages in this repository

### Step 1: source preparation

This stage creates the local renamed source-data layer from the original Oxford storage setup.

### Step 2: raw-data preparation

This stage converts the renamed source-data layer into filtered, framework-ready EEGLAB raw datasets and writes the final `dataset_list.csv`.

### Steps 3–7: framework instantiation on the Oxford dataset

These steps instantiate the framework workflow on the prepared Oxford datasets.

### Step 8: JASP-ready export for downstream statistical analysis

This stage reshapes selected screened outputs and study metadata into the final subject-level tables used for downstream analysis in JASP.

## Step 1: source preparation

Scripts:

- `step_1_source_1_create_dataset_list_prelim.m`
- `step_1_source_2_find_missing.m`
- `step_1_source_3_add_renames.m`
- `step_1_source_4_create_source.m`

### What Step 1 does

Step 1 reads the MedSciNet export, identifies the relevant Oxford EEG source files on the remote storage system, determines their source format, checks for expected sidecar files, derives BIDS-style local filenames and paths, and copies the source files into a local `data/source/` structure.

This stage supports multiple Oxford source-file situations, including:

- legacy project naming (includes Petal dataset)
- already BIDS-like project naming
- the Poppi trial special-case folder structure on the remote server

### Main outputs

- `data_lists/dataset_list_prelim.xlsx`
- renamed source files under `data/source/`

### Important user understanding points

This stage is Oxford-specific. It reflects the original storage and file-format conventions of the Oxford dataset and is not intended as a general framework stage.

It also does **not** yet produce the raw EEGLAB `.set` files required by the framework. Its role is to create a clean local source-data layer that can be converted in Step 2.

## Step 2: raw-data preparation

Scripts:

- `step_2_raw_1_get_events.m`
- `step_2_raw_2_filter_events.m`
- `step_2_raw_3_add_reformats.m`
- `step_2_raw_4_create_raw.m`
- `step_2_raw_5_adjust_latencies.m`
- `step_2_raw_6_get_standardised_events.m`
- `step_2_raw_7_get_channels.m`
- `step_2_raw_8_filter_channels.m`
- `step_2_raw_9_create_dataset_list.m`

### What Step 2 does

Step 2 takes the renamed local source files created in Step 1 and turns them into the framework-ready raw data layer.

In practical terms, it:

- inventories source-file event annotations
- creates user-editable event annotation summaries
- allows event-based dataset filtering
- derives reformatted paths and filenames for raw `.set` outputs
- converts Curry 7, Curry 8, and XDF files into EEGLAB `.set`
- optionally applies event-latency correction
- inventories the standardised `EEG.event.type` values in the raw `.set` files
- inventories raw channel labels
- allows channel-based dataset filtering
- creates the final `data_lists/dataset_list.csv`

### Main outputs

- raw `.set` files under `data/raw/`
- event annotation outputs in `data/info_prelim/event_annotations/`
- event-type outputs in `data/info_prelim/event_types/`
- channel outputs in `data/info_prelim/channels/`
- updated `dataset_list_prelim.xlsx`
- final `data_lists/dataset_list.csv`

### Important user input and inspection points

Step 2 includes several inspect-edit-continue checkpoints. It should not be treated as fully automatic.

#### Event annotation mapping

`step_2_raw_1_get_events.m` creates:

- per-file annotation inventories
- `data/info_prelim/event_annotations/event_annotation_summary.csv`

The user is expected to inspect this summary and populate the `Type` column, mapping raw annotation labels onto the standardised event types that will later appear in `EEG.event.type`.

#### Event filtering

The same annotation summary contains the user-editable columns:

- `Filter_AND`
- `Filter_OR`
- `Filter_NOT`

These are used by `step_2_raw_2_filter_events.m` to exclude datasets based on event-content rules.

#### Optional latency correction

The annotation summary also contains `LatencyCorrect`, and `dataset_list_prelim.xlsx` contains `latency_correct`.

These allow the user to flag:

- which event annotations should be latency-corrected
- which files should receive that correction

`step_2_raw_5_adjust_latencies.m` then applies the user-defined fixed shift in milliseconds.

#### Channel filtering

`step_2_raw_7_get_channels.m` creates:

- per-file channel inventories
- `data/info_prelim/channels/channel_summary.csv`

The user can populate:

- `Filter_AND`
- `Filter_OR`
- `Filter_NOT`

and `step_2_raw_8_filter_channels.m` will then exclude datasets based on those rules.

### Output handed forward to the framework

By the end of Step 2, the repository has produced the exact prerequisites required by the framework steps:

- raw EEGLAB `.set` files in `data/raw/`
- a final `data_lists/dataset_list.csv`
- standardised `EEG.event.type` values in the raw datasets
- a filtered included dataset set suitable for framework processing

So Step 2 is the point at which Oxford-specific raw-data preparation ends and the framework workflow can begin.

## Steps 3–7: framework instantiation

### What this middle block does in `simple-oxford`

Steps 3–7 instantiate the framework workflow on the prepared Oxford dataset.

In practical terms, this middle block:

- preprocesses and epochs the raw EEGLAB datasets
- extracts QC and NRF-derived quantities
- exports per-dataset and pooled summaries
- performs explicit epoch–channel screening
- runs post-screening plausibility checks

### Mapping between `simple-oxford` and `simple-framework`

The mapping is:

- `simple-oxford` Step 3 = `simple-framework` Step 1 (`proc`)
- `simple-oxford` Step 4 = `simple-framework` Step 2 (`quant`)
- `simple-oxford` Step 5 = `simple-framework` Step 3 (`sum`)
- `simple-oxford` Step 6 = `simple-framework` Step 4 (`screen`)
- `simple-oxford` Step 7 = `simple-framework` Step 5 (`check`)

### Where to find the detailed documentation

The detailed explanation of these framework-instantiating steps is intentionally not duplicated here.

For:

- the conceptual rationale of the framework
- the detailed step-by-step explanation of the processing, quantification, summarisation, screening, and checking stages
- the framework-specific user intervention points
- and the interpretation of framework outputs

see the **`simple-framework` repository README**.

The Step 3–7 scripts themselves live and run in `simple-oxford`; `simple-framework` supplies their detailed common documentation and is not imported at runtime.

### Main outputs passed forward from this block

The outputs most relevant for Step 8 include:

- screened pooled QC features
- screened pooled NRF features
- screened pooled epoch outputs
- and the broader set of framework-generated processed, summary, and screening outputs

In practice, the screened pooled QC and NRF feature tables are the main EEG-derived files carried forward into the Oxford-specific JASP export step.

## Step 8: JASP-ready export

Scripts:

- `step_8_jasp_1_data_prep_eeg_qc.m`
- `step_8_jasp_2_data_prep_eeg_nrf.m`
- `step_8_jasp_3_data_prep_eeg_combine.m`
- `step_8_jasp_4_data_prep_other.m`
- `step_8_jasp_5_data_prep_combine_all.m`
- `step_8_jasp_6_add_bvt_cols.m`
- `step_8_jasp_7_sample_details.m`

### What Step 8 does

Step 8 is the Oxford-specific export stage that takes selected screened outputs from the framework block and reshapes them into final subject-level tables for downstream statistical analysis in JASP.

Across its seven data-preparation and export scripts, Step 8:

- reshapes screened QC features into a one-row-per-subject table
- reshapes screened NRF magnitudes into a one-row-per-subject table
- combines the EEG-derived tables
- derives selected study metadata from MedSciNet, including:
  - trial arm
  - heel-lance sleep state
- combines EEG and non-EEG variables into a single subject-level table
- adds columns distinguishing:
  - the current reanalysis screening
  - and the cohort used in the published Petal analysis
- exports a sample-details table

Step 8 also includes `step_8_jasp_9_nrf_details.m`, a separate read-only inspection utility that loads and displays NRF details. It does not modify its inputs or save tables or figures; its only file output is the standard Command Window log.

### Main outputs

Step 8 writes:

- `data/jasp/jasp_data_eeg_qc.csv`
- `data/jasp/jasp_data_eeg_nrf.csv`
- `data/jasp/jasp_data_eeg.csv`
- `data/jasp/jasp_data_other.csv`
- `data/jasp/jasp_data_all.csv`
- `data/jasp/jasp_sample_details.csv`

The practical endpoint is `jasp_data_all.csv`, which is the final combined subject-level table for downstream Oxford analyses in JASP.

### Relation to the Oxford dataset and downstream analyses

Step 8 is Oxford-specific and analysis-specific. It is not part of the general framework itself.

Its role is to package selected screened EEG-derived outputs and selected trial metadata into the exact tabular form needed for the downstream Oxford analyses reported in the methods paper.

## Points where user input or inspection is required

This repository includes several manual decision points.

### During Step 1

- review the generated source-file inventory
- check missing-file outputs in `dataset_list_prelim.xlsx`
- inspect the derived renamed filenames and destination paths if needed

### During Step 2

- inspect event annotation inventories
- populate the `Type` column in `event_annotation_summary.csv`
- optionally define event filtering rules
- optionally define latency-correction flags
- inspect channel inventories
- optionally define channel filtering rules

### During Steps 3–7

The detailed user intervention points within the framework block are documented in the `simple-framework` README.

At a high level, those steps include their own inspection and decision points around:

- processing configuration
- quantification setup
- summary export choices
- screening decisions
- post-screening plausibility checks

### During Step 8

Step 8 is more constrained than the earlier stages, but it still assumes that:

- the required MedSciNet input files are present
- required study metadata columns exist and are correctly populated
- the screened EEG-derived inputs exist and match the expected schema

## Key outputs produced by this repository

Across the full repository, the most important practical outputs are:

- the local renamed source-data layer in `data/source/`
- the raw EEGLAB `.set` layer in `data/raw/`
- the final `data_lists/dataset_list.csv`
- framework outputs produced by the middle block
- screened pooled QC and NRF tables
- the final JASP-ready subject-level tables in `data/jasp/`
- per-script log files in `logs/`

## Logging and provenance

The repository includes multiple audit and provenance features.

### Command Window logs

All runnable scripts write to per-script log files in `logs/` via `log_command_window.m`.

### Structured staged outputs

The repository is structured so that the main stages produce explicit intermediate files rather than hiding all state inside a single script run. That makes the Oxford-specific preparation, framework instantiation, and JASP export stages easier to inspect and audit.

### Framework-side provenance

Within the middle framework block, additional provenance and audit features are documented in the `simple-framework` README, including the screening package and related screening outputs.

## Study-specific note on the Oxford dataset

The Oxford dataset analysed in this repository is the **Petal clinical trial dataset**. This repository supports the Oxford-side reanalysis used in the methods paper by taking that dataset from its original source-file setup through framework-based EEG processing and screening to the final subject-level export used for downstream statistical analysis.
