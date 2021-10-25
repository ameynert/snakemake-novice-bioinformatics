###
# Snakefile you should have at the start of Episode 13
###

# Configuration
configfile: "config.yaml"
# Changed print() statements to logger.info() because print() interferes with --dag and
# we get the error "display: no decode delegate for this image format"
logger.info("Config is: " + str(config))

### config.yaml contents is:
# salmon_kmer_len: "31"
# trimreads_qual_threshold: "20"
# trimreads_min_length: "100"
# conditions: ["etoh60", "temp33", "ref"]
# replicates: ["1", "2", "3"]

# Input conditions and replicates to process
CONDITIONS = config["conditions"]
REPLICATES = config["replicates"]
logger.info("Conditions are: " + str(CONDITIONS))
logger.info("Replicates are: " + str(REPLICATES))

# Rule to make all counts and compile the results in two files
rule all_counts:
  input:
    untrimmed = expand( "reads.{cond}_{rep}_{end}.fq.count",   cond  = CONDITIONS,
                                                               rep   = REPLICATES,
                                                               end   = ["1", "2"] ),
    trimmed   = expand( "trimmed.{cond}_{rep}_{end}.fq.count", cond  = CONDITIONS,
                                                               rep   = REPLICATES,
                                                               end   = ["1", "2"] ),
  output:
    untrimmed = "untrimmed_counts_concatenated.txt",
    trimmed   = "trimmed_counts_concatenated.txt",
  shell:
    "cat {input.untrimmed} > {output.untrimmed} ; cat {input.trimmed} > {output.trimmed}"

# Generic read counter rule using wildcards and placeholders,
# which can count trimmed and untrimmed reads.
rule countreads:
  output: "{indir}.{sample}.fq.count"
  input:  "{indir}/{sample}.fq"
  shell:
    "echo $(( $(wc -l <{input}) / 4 )) > {output}"

# Variable trim length for trimreads
def min_length_func(wildcards):
    read_name = wildcards.sample
    min_length = "100" if (read_name.endswith("1")) else "80"
    return min_length

# Trim any FASTQ reads for base quality
rule trimreads:
  output: temporary("trimmed/{sample}.fq")
  input:  "reads/{sample}.fq"
  params:
    qual_threshold = config["trimreads_qual_threshold"],
    min_length     = min_length_func,
  shell:
    "fastq_quality_trimmer -t {params.qual_threshold} -l {params.min_length} -o {output} <{input}"

# Generic zipper command
rule gzip_fastq:
    output: "{afile}.fq.gz"
    input:  "{afile}.fq"
    shell:
        "gzip -nc {input} > {output}"

# Kallisto quantification of one sample.
# Modified to declare the whole directory as the output.
rule kallisto_quant:
    output: directory("kallisto.{sample}")
    input:
        index = "Saccharomyces_cerevisiae.R64-1-1.kallisto_index",
        fq1   = "trimmed/{sample}_1.fq",
        fq2   = "trimmed/{sample}_2.fq",
    threads: 4
    shell:
     r"""mkdir {output}
         kallisto quant -t {threads} -i {input.index} -o {output} {input.fq1} {input.fq2} >& {output}/kallisto_quant.log
      """

rule kallisto_index:
    output:
        idx = "{strain}.kallisto_index",
        log = "{strain}.kallisto_log",
    input:
        fasta = "transcriptome/{strain}.cdna.all.fa.gz"
    shell:
        "kallisto index -i {output.idx} {input.fasta} >& {output.log}"

rule fastqc:
    output:
        html = "{indir}.{sample}_fastqc.html",
        zip  = "{indir}.{sample}_fastqc.zip"
    input:  "{indir}/{sample}.fq"
    shell:
       r"""fastqc -o . {input}
           mv {wildcards.sample}_fastqc.html {output.html}
           mv {wildcards.sample}_fastqc.zip  {output.zip}
        """

rule salmon_quant:
    output: directory("salmon.{sample}")
    input:
        index = "Saccharomyces_cerevisiae.R64-1-1.salmon_index",
        fq1   = "trimmed/{sample}_1.fq.gz",
        fq2   = "trimmed/{sample}_2.fq.gz",
    conda: "salmon-1.2.1.yaml"
    threads: 4
    shell:
        "salmon quant -p {threads} -i {input.index} -l A -1 {input.fq1} -2 {input.fq2} --validateMappings -o {output}"

rule salmon_index:
    output:
        idx = directory("{strain}.salmon_index")
    input:
        fasta = "transcriptome/{strain}.cdna.all.fa.gz"
    params:
        kmer_len = config.get("salmon_kmer_len", "33")
    conda: "salmon-1.2.1.yaml"
    shell:
        "salmon index -t {input.fasta} -i {output.idx} -k {params.kmer_len}"

# A version of the MultiQC rule that ensures nothing unexpected is hoovered up by multiqc,
# by linking the files into a temporary directory.
# Note that this requires the *kallisto_quant* rule to be amended so that it has a directory
# as the output, and that directory contains the console log.
rule multiqc:
    output:
        mqc_out = directory('multiqc_out'),
        mqc_in  = directory('multiqc_in'),
    input:
        salmon =   expand("salmon.{cond}_{rep}", cond=CONDITIONS, rep=REPLICATES),
        kallisto = expand("kallisto.{cond}_{rep}", cond=CONDITIONS, rep=REPLICATES),
        fastqc =   expand("reads.{cond}_{rep}_{end}_fastqc.zip", cond=CONDITIONS, rep=REPLICATES, end=["1","2"]),
    shell:
      r"""mkdir {output.mqc_in}
          ln -snr -t {output.mqc_in} {input}
          multiqc {output.mqc_in} -o {output.mqc_out}
       """
