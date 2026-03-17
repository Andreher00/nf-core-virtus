/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { FASTQC                  } from '../modules/nf-core/fastqc/main'
include { MULTIQC                 } from '../modules/nf-core/multiqc/main'
include { paramsSummaryMap        } from 'plugin/nf-schema'
include { paramsSummaryMultiqc    } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML  } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText  } from '../subworkflows/local/utils_nfcore_virtus_pipeline'

include { STAR_GENOMEGENERATE as STAR_GENOMEGENERATE_HUMAN } from '../modules/nf-core/star/genomegenerate/main'
include { STAR_GENOMEGENERATE as STAR_GENOMEGENERATE_VIRUS } from '../modules/nf-core/star/genomegenerate/main'
include { SAMTOOLS_VIEW                                    } from '../modules/nf-core/samtools/view/main'
include { FASTP                                            } from '../modules/nf-core/fastp/main'
include { STAR_ALIGN as STAR_ALIGN_HUMAN                   } from '../modules/nf-core/star/align/main'
include { STAR_ALIGN as STAR_ALIGN_VIRUS                   } from '../modules/nf-core/star/align/main'
include { SALMON_QUANT                                     } from '../modules/nf-core/salmon/quant/main'
include { SAMTOOLS_COLLATEFASTQ                            } from '../modules/nf-core/samtools/collatefastq/main'
include { SAMTOOLS_FASTQ                                   } from '../modules/nf-core/samtools/fastq/main'
include { BAMFILTERPOLYX                                   } from '../modules/local/bamfilterpolyx/main'
include { KZFILTER as KZFILTER_SE                          } from '../modules/local/kzfilter/main'
include { KZFILTER as KZFILTER_PE                          } from '../modules/local/kzfilter/main'
include { FASTQPAIR                                        } from '../modules/local/fastqpair/main'
include { SAMTOOLS_COVERAGE                                } from '../modules/nf-core/samtools/coverage/main'
include { MKSUMMARYVIRUSCOUNT                              } from '../modules/local/mksummaryviruscount/main'
include { MKSUMMARYSTATS                                   } from '../modules/local/mksummarystats/main'
/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow VIRTUS {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    main:
    

    ch_versions = channel.empty()
    ch_multiqc_files = channel.empty()



    ch_fasta_human      = params.fasta_human ? channel.value( [ [:], file(params.fasta_human) ] ) : channel.value( [ [:], [] ] )
    ch_gtf              = params.gtf ? channel.value( [ [:], file(params.gtf) ] ) : channel.value( [ [:], [] ] )

    ch_fasta_virus      = params.fasta_virus ? channel.value( [ [:], file(params.fasta_virus) ] ) : channel.value( [ [:], [] ] )


    // Human STAR index
    if (params.star_index_human && file(params.star_index_human).exists()) {
        // Use pre-built index
        ch_star_index_human = channel.value([ [:], file(params.star_index_human) ] )
    } else if (params.fasta_human) {
        if (params.star_index_human) {
            log.warn "WARNING: Provided STAR index not found at: ${params.star_index_human}"
            log.warn "Generating STAR index from FASTA instead..."
        }
        // Generate index from FASTA
        STAR_GENOMEGENERATE_HUMAN(ch_fasta_human, ch_gtf)
        ch_star_index_human = STAR_GENOMEGENERATE_HUMAN.out.index
        ch_versions = ch_versions.mix(STAR_GENOMEGENERATE_HUMAN.out.versions.first())
    } else {
        error "ERROR: Please provide either --star_index_human or --fasta_human"
    } 

    // Virus STAR index
    if (params.star_index_virus && file(params.star_index_virus).exists()) {
        // Use pre-built index
        ch_star_index_virus = channel.value([ [:], file(params.star_index_virus) ] )
    } else if (params.fasta_virus) {
        if (params.star_index_virus) {
            log.warn "WARNING: Provided STAR index not found at: ${params.star_index_virus}"
            log.warn "Generating STAR index from FASTA instead..."
        }
        // Generate index from FASTA
        STAR_GENOMEGENERATE_VIRUS(ch_fasta_virus, channel.value([[:], []])) // No GTF for virus
        ch_star_index_virus = STAR_GENOMEGENERATE_VIRUS.out.index
        ch_versions = ch_versions.mix(STAR_GENOMEGENERATE_VIRUS.out.versions.first())
    } else {
        error "ERROR: Please provide either --star_index_virus or --fasta_virus"
    }


    //
    // MODULE: Run FastQC
    //
    FASTQC (
        ch_samplesheet
    )
    ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip.collect{ tuple -> tuple[1] })
    ch_versions = ch_versions.mix(FASTQC.out.versions.first())

    // FASTP expects a tuple with adapter FASTAs
    ch_fastp_input = ch_samplesheet
        .map { meta, reads -> 
            return [ meta, reads, params.adapter_fasta] 
        }
    FASTP (
        ch_fastp_input,
        false,       // discard_trimmed_reads
        false,       // save_trimmed_fail
        false        // save merged
    )
    ch_multiqc_files = ch_multiqc_files.mix(FASTP.out.log.collect{ tuple -> tuple[1] })

    // STAR MAPPING TO HUMAN
    STAR_ALIGN_HUMAN (
        FASTP.out.reads,    // Input reads
        ch_star_index_human,      // STAR index TODO: add support for generating index if not provided
        ch_gtf,             // GTF file (optional, pass [] if not used)
        params.star_ignore_sjdbgtf,
        params.seq_platform, 
        params.seq_center
    )
    ch_multiqc_files = ch_multiqc_files.mix(STAR_ALIGN_HUMAN.out.log_final.collect{ tuple -> tuple[1] })
    ch_versions = ch_versions.mix(STAR_ALIGN_HUMAN.out.versions.first())
    
    STAR_ALIGN_HUMAN.out.bam_sorted.view()

    input_for_samtools = STAR_ALIGN_HUMAN.out.bam_sorted_aligned
        .map{ meta, bam ->
            [meta, bam, []]
            }

    // EXTRACT UNMAPPED READS
    SAMTOOLS_VIEW (             // configured with -f 4 to extract unmapped reads
        input_for_samtools,     // input BAM files
        [[:], []],                     // No Fasta reference needed for this view operation
        [],                     // No QNAME file needed
        ''                      // No index to output
    )

    // BRANCH TO SE AND PE
    SAMTOOLS_VIEW.out.bam
        .branch { item ->
            se: item[0].single_end // If single_end is true, go to 'se' channel
            pe: !item[0].single_end // If single_end is false, go to 'pe' channel
        }
        .set { ch_unmapped_bam }

    // CONVERT PE BAM TO FASTQ
    SAMTOOLS_COLLATEFASTQ (
        ch_unmapped_bam.pe,       // input PE BAM files
        [[],[]],                  // Fasta reference (optional, usually empty for this)
        false                     // interleaved output
    )
    ch_versions = ch_versions.mix(SAMTOOLS_COLLATEFASTQ.out.versions.first())


    // CONVERT SE BAM TO FASTQ
    SAMTOOLS_FASTQ (
        ch_unmapped_bam.se,             // input SE BAM files
        false                           // interleaved output
    )
    ch_versions = ch_versions.mix(SAMTOOLS_FASTQ.out.versions.first())


    // Split PE reads for kz
    ch_split_reads = SAMTOOLS_COLLATEFASTQ.out.fastq
        .transpose()
    ch_versions = ch_versions.mix(SAMTOOLS_COLLATEFASTQ.out.versions.first())
    
    // KZ FILTER PE READS
    KZFILTER_PE(
        ch_split_reads
    )

    // Rejoin PE reads
    ch_pe_filtered = KZFILTER_PE.out.output_fq
        .groupTuple(size: 2)
        .map { meta, reads -> [meta, reads.sort { file -> file.name }] }

    FASTQPAIR(
        ch_pe_filtered
    )

    // KZ FILTER SE READS
    KZFILTER_SE(
        SAMTOOLS_FASTQ.out.other    // reads with no READ1 or READ2 flags set
    )

    // Format SE channel correctly for remixing
    ch_se_filtered = KZFILTER_SE.out.output_fq
        .map { meta, read -> [meta, [read]]}

    // We mix the results back together so downstream tools don't care about the split
    ch_fastq_for_star_virus = channel.empty()
        .mix(FASTQPAIR.out.reads)
        .mix(ch_se_filtered)


    // STAR MAPPING TO VIRUS
    STAR_ALIGN_VIRUS(
        ch_fastq_for_star_virus,      // Input reads
        ch_star_index_virus,      // STAR index 
        [[:], []],                         // No GTF for virus mapping
        params.star_ignore_sjdbgtf,
        params.seq_platform,
        params.seq_center
    )
    ch_multiqc_files = ch_multiqc_files.mix(STAR_ALIGN_VIRUS.out.log_final.collect{ tuple -> tuple[1] })
    ch_versions = ch_versions.mix(STAR_ALIGN_VIRUS.out.versions.first())

    BAMFILTERPOLYX(
        STAR_ALIGN_VIRUS.out.bam,
    )

    input_for_coverage = BAMFILTERPOLYX.out.sequence_trace
        .map{ meta, bam ->
            [meta, bam, []]   // No index needed
            }
    SAMTOOLS_COVERAGE(
        input_for_coverage,
        [[:], []], // No reference FASTA
        [[:], []],   // No FAI index
    )

    MKSUMMARYVIRUSCOUNT(
        STAR_ALIGN_HUMAN.out.log_final,   // STAR log from human mapping
        SAMTOOLS_COVERAGE.out.coverage     // Coverage from virus mapping
    )

    ch_virtus_results = MKSUMMARYVIRUSCOUNT.out.output_tsv
        .map { _meta, tsv -> tsv }
        .collect()
        .map { tsvs -> [ [ id: 'summary'], tsvs ] }

    // Run summary
    MKSUMMARYSTATS(
        ch_virtus_results,
        file(params.input)
    )


    //
    // Collate and save software versions
    //
    def topic_versions = channel.topic("versions")
        .distinct()
        .branch { entry ->
            versions_file: entry instanceof Path
            versions_tuple: true
        }

    def topic_versions_string = topic_versions.versions_tuple
        .map { process, tool, version ->
            [ process[process.lastIndexOf(':')+1..-1], "  ${tool}: ${version}" ]
        }
        .groupTuple(by:0)
        .map { process, tool_versions ->
            tool_versions.unique().sort()
            "${process}:\n${tool_versions.join('\n')}"
        }

    softwareVersionsToYAML(ch_versions.mix(topic_versions.versions_file))
        .mix(topic_versions_string)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'virtus_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        channel.fromPath(params.multiqc_config, checkIfExists: true) :
        channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
