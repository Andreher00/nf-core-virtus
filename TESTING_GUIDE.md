# Testing Guide for the Fix

## Quick Start - Test the Fix

### Option 1: Test Locally (Recommended)

1. **Checkout the fix branch:**
   ```bash
   git fetch origin
   git checkout seqera-ai/20260317-123016-fix-closure-sorting-error
   ```

2. **Run the pipeline with your sample data:**
   ```bash
   nextflow run main.nf \
     --input assets/samplesheet.csv \
     --outdir results \
     --fasta_human /path/to/human.fasta \
     --fasta_virus /path/to/virus.fasta \
     -profile docker
   ```

3. **Or with pre-built STAR indices:**
   ```bash
   nextflow run main.nf \
     --input assets/samplesheet.csv \
     --outdir results \
     --star_index_human /path/to/human_star_index \
     --star_index_virus /path/to/virus_star_index \
     -profile docker
   ```

### Option 2: Test Directly from GitHub

```bash
nextflow run Andreher00/nf-core-virtus \
  -r seqera-ai/20260317-123016-fix-closure-sorting-error \
  --input samplesheet.csv \
  --outdir results \
  --star_index_human /path/to/human_index \
  --star_index_virus /path/to/virus_index \
  -profile docker
```

## What to Look For

### ✅ Success Indicators
1. **No more closure errors** - The pipeline should run past the KZFILTER step
2. **FASTQPAIR executes** - Check for FASTQPAIR process completion
3. **Paired reads are properly sorted** - Output files in work directories should be in order

### ❌ If You Still See Errors
Check the error message carefully:
- If it's a different error, the fix worked but there may be another issue
- If it's the same closure error, please share the full error output

## Expected Pipeline Flow

With the fix, the pipeline should successfully:
1. ✅ Run FASTQC on raw reads
2. ✅ Trim reads with FASTP
3. ✅ Align to human genome with STAR
4. ✅ Extract unmapped reads with SAMTOOLS_VIEW
5. ✅ Split SE/PE reads
6. ✅ **Filter PE reads with KZFILTER** (this is where the error was)
7. ✅ **Sort and pair filtered reads** (the fixed section)
8. ✅ **Run FASTQPAIR** (should now succeed)
9. ✅ Continue with virus mapping

## Minimal Test Case

If you want a quick test just to verify the fix works:

```bash
# Run with -resume to skip completed steps
nextflow run main.nf \
  --input assets/samplesheet.csv \
  --outdir test_results \
  --star_index_human /path/to/human_index \
  --star_index_virus /path/to/virus_index \
  -profile docker \
  -resume
```

## Debugging Tips

### Check specific process outputs:
```bash
# View the work directory for KZFILTER_PE
ls -la work/**/KZFILTER_PE/

# Check FASTQPAIR inputs
nextflow log -f "name,status,workdir" | grep FASTQPAIR
```

### Enable detailed logging:
```bash
nextflow run main.nf \
  --input assets/samplesheet.csv \
  --outdir results \
  -profile docker \
  -with-trace \
  -with-report \
  -with-dag flowchart.html
```

## Compare with Main Branch

To verify the fix actually changed behavior:

```bash
# Test the broken version (main branch)
git checkout main
nextflow run main.nf --input assets/samplesheet.csv --outdir broken_test -profile docker
# Should see the error

# Test the fixed version
git checkout seqera-ai/20260317-123016-fix-closure-sorting-error
nextflow run main.nf --input assets/samplesheet.csv --outdir fixed_test -profile docker
# Should complete successfully
```

## After Testing

If the fix works:
1. Go to https://github.com/Andreher00/nf-core-virtus/pull/1
2. Review the changes
3. Merge the pull request
4. Your main branch will have the fix!

If issues persist:
1. Share the error output
2. Include the `.nextflow.log` file
3. Note which step failed

## Questions?

- Check `FIX_SUMMARY.md` for technical details
- Review the PR description: https://github.com/Andreher00/nf-core-virtus/pull/1
- The fix is a simple one-line change that should be safe to merge
