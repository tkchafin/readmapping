//
// Check input samplesheet and get read channels
//

include { SAMPLESHEET_CHECK } from '../../modules/local/samplesheet_check'
include { SAMTOOLS_FLAGSTAT } from '../../modules/nf-core/samtools/flagstat/main'


workflow INPUT_CHECK {
    take:
    samplesheet    // file: /path/to/samplesheet.csv


    main:
    ch_versions = Channel.empty()

    // Read the samplesheet
    SAMPLESHEET_CHECK ( samplesheet ).csv
    | splitCsv ( header:true, sep:',' )
    // Prepare the channel for SAMTOOLS_FLAGSTAT
    | map { row -> [row + [id: file(row.datafile).baseName], file(row.datafile, checkIfExists: true), []] }
    | set { samplesheet_rows }
    ch_versions = ch_versions.mix ( SAMPLESHEET_CHECK.out.versions.first() )

    // Get stats from each input file
    SAMTOOLS_FLAGSTAT ( samplesheet_rows )
    ch_versions = ch_versions.mix ( SAMTOOLS_FLAGSTAT.out.versions.first() )

    // Create the read channel for the rest of the pipeline
    samplesheet_rows
    | join( SAMTOOLS_FLAGSTAT.out.flagstat )
    | map { meta, datafile, dummy, stats -> create_data_channel( meta, datafile, stats ) }
    | set { reads }


    emit:
    reads                                        // channel: [ val(meta), /path/to/datafile ]
    versions = ch_versions                       // channel: [ versions.yml ]
}


// Function to get list of [ meta, reads ]
def create_data_channel ( LinkedHashMap row, datafile, stats ) {
    // create meta map
    def meta = [:]
    meta.id         = row.sample
    meta.datatype   = row.datatype

    if ( meta.datatype == "hic" || meta.datatype == "illumina" ) { 
        platform = "ILLUMINA"
    } else if ( meta.datatype == "pacbio" || meta.datatype == "pacbio_clr" ) { 
        platform = "PACBIO"
    } else if (meta.datatype == "ont") { 
        platform = "ONT"
    }
    meta.read_group  = "\'@RG\\tID:" + row.datafile.split('/')[-1].split('\\.')[0] + "\\tPL:" + platform + "\\tSM:" + meta.id.split('_')[0..-2].join('_') + "\'"

    // Read the first line of the flagstat file
    // 3127898040 + 0 in total (QC-passed reads + QC-failed reads)
    // and make the sum of both integers
    stats.withReader {
        line = it.readLine()
        def lspl = line.split()
        def read_count = lspl[0].toLong() + lspl[2].toLong()
        meta.read_count = read_count
    }

    return [meta, datafile]
}
