# Fix Summary: Invalid Method Invocation Error

## Error Diagnosed
```
groovy.lang.MissingMethodException: No signature of method: Script_114ebfb576f790a3$_runScript_closure3$_closure5$_closure7.call() 
is applicable for argument types: (ArrayList) values: [[[id:SRR8315715], /home/andrea/nf_core_virtus/nf-core-virtus/assets/SRR8315715/SRR8315715_2.fastq.gz, ...]]
```

## Root Cause
**File:** `workflows/virtus.nf`, **Line:** 175

The issue was in the nested closure inside the `.map()` operator:

```groovy
// ❌ INCORRECT - Nested closure causing the error
.map { meta, reads -> [meta, reads.sort { read -> read.name }]}
```

The problem:
- The `reads` variable is already a list of Path objects
- When calling `.sort { read -> read.name }`, the closure `{ read -> read.name }` was receiving the entire ArrayList instead of individual elements
- This created an invalid method invocation with nested ArrayList arguments

## The Fix Applied

**Changed line 175 from:**
```groovy
.map { meta, reads -> [meta, reads.sort { read -> read.name }]}
```

**To:**
```groovy
.map { meta, reads -> [meta, reads.sort()] }
```

## Why This Works

1. **`.sort()` without arguments** uses the natural ordering of Path objects (lexicographic by filename)
2. **No nested closure** means no invalid ArrayList being passed around
3. **Simpler and cleaner** - Path objects naturally sort by filename anyway

## Alternative Solutions

If you need custom sorting by filename:

```groovy
// Option 1: Explicit variable assignment
.map { meta, reads -> 
    def sorted = reads.sort { it.name }
    [meta, sorted]
}

// Option 2: Use sort with method reference (Groovy style)
.map { meta, reads -> [meta, reads.sort { it.name }] }

// Option 3: Use collectEntries if you need more control
.map { meta, reads -> 
    def sorted = reads.collect().sort { it.name }
    [meta, sorted]
}
```

## Testing the Fix

Run your pipeline again:
```bash
nextflow run main.nf --input assets/samplesheet.csv --outdir results -profile docker
```

The error should now be resolved, and the paired-end reads should be properly sorted and passed to FASTQPAIR.

## Related Code Section

The complete corrected section (lines 172-178):
```groovy
// Rejoin PE reads
ch_pe_filtered = KZFILTER_PE.out.output_fq
    .groupTuple(size: 2)
    .map { meta, reads -> [meta, reads.sort()] }

FASTQPAIR(
    ch_pe_filtered
)
```
