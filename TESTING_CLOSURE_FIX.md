# Testing Guide for Closure and Method Invocation Fixes

This document provides comprehensive testing instructions for the closure and method invocation fixes in the VIRTUS pipeline.

## Problems Fixed

### 1. Invalid Method Invocation on `.sort()` for PE Reads
**Error:** `Invalid method invocation`

**Root Cause:** The `.sort()` method was being called without a closure parameter on a list of file paths, causing ambiguous method resolution when processing paired-end reads.

**Location:** Line 178 in `workflows/virtus.nf`

**Solution:** Added explicit closure parameter: `.sort { file -> file.name }` to sort by filename

**Code Change:**
```groovy
// Before (broken)
ch_pe_filtered = KZFILTER_PE.out.output_fq
    .groupTuple(size: 2)
    .map { meta, reads -> [meta, reads.sort()] }

// After (fixed)
ch_pe_filtered = KZFILTER_PE.out.output_fq
    .groupTuple(size: 2)
    .map { meta, reads -> [meta, reads.sort { file -> file.name }] }
```

### 2. Implicit Closure Parameters in MultiQC File Collection
**Root Cause:** Using implicit `item` parameter names in collect operations which can cause issues with strict syntax mode and make code harder to read.

**Locations:** Lines 94, 108, 119, 205 in `workflows/virtus.nf`

**Solution:** Changed from `collect{item -> item[1]}` to explicit `collect{ tuple -> tuple[1] }`

**Code Changes:**
```groovy
// Before (ambiguous)
ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{item -> item[1]})

// After (explicit)
ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{ tuple -> tuple[1] })
```

## Why These Fixes Matter

### Single-End (SE) vs Paired-End (PE) Data
The VIRTUS pipeline processes both SE and PE sequencing data differently:

1. **PE Data Path:**
   - Split reads → KZ filter each read separately → Group back together → Sort → Process

2. **SE Data Path:**
   - KZ filter single read → Format as list → Process

The `.sort()` fix is **critical for PE data** because:
- After `groupTuple(size: 2)`, we have a list of 2 file paths (R1 and R2)
- These need to be sorted consistently (e.g., alphabetically by filename)
- Without an explicit closure, Groovy's method resolution fails
- With the closure `{ file -> file.name }`, sorting is explicit and reliable

The MultiQC collection fixes improve:
- Code clarity and maintainability
- Compatibility with Nextflow strict syntax mode
- Consistency across the codebase

## Testing Instructions

### Quick Test (5-10 minutes)

Test with the minimal test profile to verify basic functionality:

```bash
cd nf-core-virtus

# Test with SE data
nextflow run . -profile test,docker --outdir results_test_se

# Test with PE data (if available in test profile)
nextflow run . -profile test,docker --outdir results_test_pe
```

**Expected Outcome:**
- ✅ Workflow completes successfully
- ✅ No "Invalid method invocation" errors
- ✅ MultiQC report generated
- ✅ All intermediate files created

### Comprehensive Test (30-60 minutes)

Test with real data covering both SE and PE scenarios:

#### 1. Prepare Test Data

Create a samplesheet for SE data:
```csv
sample,fastq_1,fastq_2,strandedness
SAMPLE_SE,/path/to/se_sample.fastq.gz,,auto
```

Create a samplesheet for PE data:
```csv
sample,fastq_1,fastq_2,strandedness
SAMPLE_PE,/path/to/pe_sample_R1.fastq.gz,/path/to/pe_sample_R2.fastq.gz,auto
```

#### 2. Run SE Test

```bash
nextflow run . \
  --input samplesheet_se.csv \
  --outdir results_se \
  --fasta_human /path/to/human_genome.fa \
  --fasta_virus /path/to/virus_genome.fa \
  --gtf /path/to/genes.gtf \
  -profile docker
```

**Key Checkpoints:**
- ✅ KZFILTER_SE process completes
- ✅ SAMTOOLS_FASTQ extracts unmapped reads
- ✅ STAR_ALIGN_VIRUS processes SE reads
- ✅ No errors in `.nextflow.log`

#### 3. Run PE Test

```bash
nextflow run . \
  --input samplesheet_pe.csv \
  --outdir results_pe \
  --fasta_human /path/to/human_genome.fa \
  --fasta_virus /path/to/virus_genome.fa \
  --gtf /path/to/genes.gtf \
  -profile docker
```

**Key Checkpoints:**
- ✅ KZFILTER_PE processes both R1 and R2
- ✅ `.groupTuple(size: 2)` groups files correctly
- ✅ `.sort { file -> file.name }` orders files consistently
- ✅ FASTQPAIR validates paired reads
- ✅ STAR_ALIGN_VIRUS processes PE reads
- ✅ No "Invalid method invocation" errors

#### 4. Mixed Dataset Test

Create a samplesheet with both SE and PE samples:
```csv
sample,fastq_1,fastq_2,strandedness
SAMPLE_SE,/path/to/se_sample.fastq.gz,,auto
SAMPLE_PE,/path/to/pe_sample_R1.fastq.gz,/path/to/pe_sample_R2.fastq.gz,auto
```

```bash
nextflow run . \
  --input samplesheet_mixed.csv \
  --outdir results_mixed \
  --fasta_human /path/to/human_genome.fa \
  --fasta_virus /path/to/virus_genome.fa \
  --gtf /path/to/genes.gtf \
  -profile docker
```

**Key Checkpoints:**
- ✅ Both SE and PE samples processed correctly
- ✅ Channel mixing works properly
- ✅ MultiQC report includes all samples
- ✅ No errors in workflow execution

### Edge Cases

#### Test 1: Single Sample (SE)
```bash
# Minimal samplesheet with one SE sample
nextflow run . --input single_se.csv --outdir results_single_se -profile docker
```

#### Test 2: Single Sample (PE)
```bash
# Minimal samplesheet with one PE sample
nextflow run . --input single_pe.csv --outdir results_single_pe -profile docker
```

#### Test 3: Multiple PE Samples
```bash
# Samplesheet with 3+ PE samples to test grouping and sorting
nextflow run . --input multi_pe.csv --outdir results_multi_pe -profile docker
```

## Validation Checklist

After running tests, verify:

### Workflow Execution
- [ ] No errors in `.nextflow.log`
- [ ] All processes completed successfully
- [ ] Expected number of output files generated
- [ ] Workflow timeline shows no failed tasks

### Output Files
- [ ] MultiQC report generated: `results/multiqc/multiqc_report.html`
- [ ] FASTQC results for all samples
- [ ] FASTP trimming logs
- [ ] STAR alignment logs (human and virus)
- [ ] Coverage statistics
- [ ] Summary TSV files

### MultiQC Report Content
- [ ] All samples appear in the report
- [ ] FastQC sections present
- [ ] Trimming statistics included
- [ ] Alignment statistics shown
- [ ] No missing data or errors reported

### PE-Specific Validation
- [ ] R1 and R2 reads processed in correct order
- [ ] FASTQPAIR validation passed
- [ ] Paired read counts match expectations

### SE-Specific Validation
- [ ] Single reads processed correctly
- [ ] No pairing errors
- [ ] Read counts consistent through pipeline

## Troubleshooting

### Error: "Invalid method invocation"
**Likely Cause:** Running old version of code without the `.sort()` fix

**Solution:** 
1. Confirm you're on the correct branch: `git status`
2. Verify line 178 has: `.map { meta, reads -> [meta, reads.sort { file -> file.name }] }`
3. Clean work directory: `rm -rf work/`
4. Retry the run

### Error: "Variable was not declared"
**Likely Cause:** Closure parameter scope issue

**Solution:**
1. Check that all collect operations use explicit parameters
2. Verify no implicit `it` parameters in closures
3. Review recent code changes

### Error: Channel type mismatch
**Likely Cause:** SE/PE channel mixing issue

**Solution:**
1. Verify SE reads are wrapped in list: `[meta, [read]]`
2. Verify PE reads are in list: `[meta, [read1, read2]]`
3. Check channel mixing logic around line 192

### MultiQC report missing samples
**Likely Cause:** Collect operations not gathering all files

**Solution:**
1. Check that all MultiQC file collections completed
2. Verify files exist in work directories
3. Check `.nextflow.log` for collection warnings

## Performance Notes

- **SE data:** Generally faster as no pairing/grouping operations needed
- **PE data:** Requires grouping, sorting, and pairing validation
- **Mixed datasets:** Should handle both types seamlessly

## Expected Runtime

| Dataset Type | Size | Expected Runtime |
|--------------|------|------------------|
| Test profile | ~100MB | 5-10 minutes |
| Small SE | 1-2GB | 20-40 minutes |
| Small PE | 1-2GB | 30-60 minutes |
| Large PE | 10GB+ | 2-4 hours |

Times vary based on compute resources and STAR index generation.

## Reporting Issues

If you encounter issues after applying these fixes:

1. **Collect information:**
   - Error message from console
   - Relevant lines from `.nextflow.log`
   - Sample type (SE/PE)
   - Nextflow version: `nextflow -version`

2. **Check work directory:**
   - Navigate to failed task work directory
   - Check `.command.err` and `.command.out`
   - Verify input files exist and are readable

3. **Create issue with:**
   - Description of the problem
   - Steps to reproduce
   - Error logs
   - Data type being processed

## Summary

These fixes ensure the VIRTUS pipeline correctly handles:
- ✅ Explicit sorting of paired-end read files
- ✅ Clear closure parameter naming
- ✅ Both SE and PE data processing
- ✅ Mixed SE/PE datasets
- ✅ Proper MultiQC file collection

The changes maintain backward compatibility while improving code clarity and robustness.
