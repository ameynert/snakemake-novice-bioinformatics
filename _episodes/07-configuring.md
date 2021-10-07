---
title: "Configuring workflows"
teaching: 20
exercises: 20
questions:
- "How do I separate my rules from my configuration?"
objectives:
- "Add parameters to rules"
- "Use configuration files and command line options to set the parameters"
keypoints:
- "Break out significant options into rule parameters"
- "Use a YAML config file to separate your configuration from your workflow logic"
- "Decide if different config items should be mandatory or else have a default"
- "Reference the config file in your Snakefile or else on the command line with `--configfile`"
- "Override or add config values using `--config name1=value1 name2=value2` and end the list with `--`"
---
*For reference, [this is the Snakefile](../code/ep07.Snakefile) you should have to start the episode.*

## Adding parameters (params) to rules

So far, we've written rules with `input`, `output` and `shell` parts. Another useful section you can add to
a rule is `params`.

Consider the "trimreads" rule we defined earlier in the course.

~~~
rule trimreads:
  output: "trimmed/{asample}.fq"
  input:  "reads/{asample}.fq"
  shell:
    "fastq_quality_trimmer -t 20 -l 100 -o {output} <{input}"
~~~

Can you remember what the `-t 20` and `-l 100` parameters do without referring back to the manual? Probably not!
Adding comments in the Snakefile would certainly help, but we can also make important settings into parameters.

~~~
rule trimreads:
  output: "trimmed/{asample}.fq"
  input:  "reads/{asample}.fq"
  params:
    qual_threshold = "20",
    min_length     = "100",
  shell:
    "fastq_quality_trimmer -t {params.qual_threshold} -l {params.min_length} -o {output} <{input}"
~~~

Now it is a little clearer what these numbers mean. Use of parameters does not give you extra functionality but it is
good practise put settings like these into parameters as it makes the whole rule more readable.

> ## Exercise
>
> Modify the existing salmon_index rule so that the `-k` setting (k-mer length) is a parameter.
>
> Change the length to 33 and re-build the index with the amended rule.
>
> > ## Solution
> >
> > ~~~
> > rule salmon_index:
> >     output:
> >         idx = directory("{strain}.salmon_index")
> >     input:
> >         fasta = "transcriptome/{strain}.cdna.all.fa.gz"
> >     params:
> >         kmer_len = "33"
> >     shell:
> >         "salmon index -t {input.transcriptome} -i {output.index} -k {params.kmer_len}"
> > ~~~
> >
> > ~~~
> > snakemake -j1 -p -f Saccharomyces_cerevisiae.R64-1-1.salmon_index
> > ~~~
> >
> > Notes:
> >
> > * You can choose a different parameter name, but it must be a valid identifier - no spaces or hyphens.
> > * Changing the parameters does automatically trigger Snakemake to re-run the rule (remember it only looks
> >   at file modification times) so you need to use `-f` (or `-R` or `-F`) to force the job to be re-run.
> >
> {: .solution}
{: .challenge}

## Making Snakefiles configurable

In general, it's good practise to break out parameters that you intend to change into a separate file. That
way you can re-run the pipeline on new input data, or with alternative settings, but you don't
need to edit the Snakefile itself.

We'll save the following lines into a file named *config.yaml*.

~~~
salmon_kmer_len: "31"
trimreads_qual_threshold: "20"
trimreads_min_length: "100"
~~~

This file is in YAML format. This format allows you to capture complex data structures but we'll just use it to
store some name+value pairs. We can then reference these values within the Snakefile via the **config**
object.

~~~
rule trimreads:
  output: "trimmed/{asample}.fq"
  input:  "reads/{asample}.fq"
  params:
    qual_threshold = config["trimreads_qual_threshold"],
    min_length     = config.get("trimreads_min_length", "100"),
  shell:
    "fastq_quality_trimmer -t {params.qual_threshold} -l {params.min_length} -o {output} <{input}"
~~~

In the above example, the **trimreads_qual_threshold** value must be supplied in the config, but the
**trimreads_min_length** can be omitted, and then the default of "100" will be used.

If you are a Python programmer you'll recognise the syntax here. If not, then just take note that the first form
uses *square brackets* and the other uses `.get(...)` with *regular brackets*. Both the config entry name and the
default value should be in quotes.

> ## Note
>
> You don't have to always use *config* in conjunction with *params* like this, but it's often a good idea to do so.
>
{: .callout}

The final step is to tell Snakemake about your config file, by referencing it on the command line:

~~~
$ snakemake --configfile=config.yaml ...
~~~

> ## Exercise
>
> Fix the `salmon_index` rule to use `salmon_kmer_len` as in the config file sample above. Use a default of "33" if
> no config setting is supplied.
>
> Run Snakemake in *dry run* mode (`-n`) to check that this is working as expected.
>
> > ## Solution
> >
> > Rule is as before, aside from:
> >
> > ~~~
> > params:
> >     kmer_len = config.get("salmon_kmer_len", "33")
> > ~~~
> >
> > If you run Snakemake with the `-n` and `-p` flags and referencing the config file, you should see that the
> > command being printed has the expected value of *31*.
> >
> > ~~~
> > $ snakemake -n -p -f --configfile=config.yaml Saccharomyces_cerevisiae.R64-1-1.salmon_index
> > ~~~
> >
> > *Note that if you try to run Snakemake with no config
> > file you will now get a **KeyError** regarding **trimreads_qual_threshold**. Even though you are not using the
> > **trimreads** rule, Snakemake needs a setting for all mandatory parameters.*
> >
> {: .solution}
{: .challenge}

Before proceeding, we'll tweak the Snakefile in a couple of ways:

1. Set a default `configfile` option so we don't need to type it on every command line.
1. Get Snakemake to print out the config whenever it runs.

Add the following lines right at the top of the Snakefile.

~~~
configfile: "config.yaml"
print("Config is: ", config)
~~~

Finally, as well as the `--configfile` option to Snakemake there is the `--config` option which sets individual
configuration parameters.

~~~
$ snakemake -npf --configfile=config.yaml --config salmon_kmer_len=23 -- Saccharomyces_cerevisiae.R64-1-1.salmon_index/
~~~

This is all getting quite complex, so in summary:

* Snakemake loads the `--configfile` supplied on the command line, or else defaults to the one named in the Snakefile, or else
  runs with no config file.
* Individual `--config` items on the command line always take precedence over settings in the config file.
* You can set multiple `--config` values on the command line and you always need to put `--` to end the list.
* Use the `config.get("item_name", "default_val")` syntax to supply a default value which takes lowest precedence.
* Use `config["item_name"]` syntax to have a mandatory configuration option.

> ## Exercise
>
> Modify the *Snakefile* and *config.yaml* so that you are setting the *CONDITIONS* and *REPLICATES* in the config file.
> Lists in YAML use the same syntax as Python, with square brackets and commas, so you can copy the lists you already have.
> Note that you're not expected to modify any rules here.
>
> Re-run the workflow to make a report on *just replicates 2 and 3*. Check the MultiQC report to see that it really
> does have just these replicates in there.
>
> > ## Solution
> >
> > In *config.yaml* add the lines:
> >
> > ~~~
> > conditions: ["etoh60", "temp33", "ref"]
> > replicates: ["1", "2", "3"]
> > ~~~
> >
> > In the *Snakefile* we can reference the *config* while setting the global variables. There are no *params* to add
> > because these settings are altering the selection of jobs to be added to the DAG, rather than just the *shell* commands.
> >
> > ~~~
> > CONDITIONS = config["conditions"]
> > REPLICATES = config["replicates"]
> > ~~~
> >
> > And for the final part we can either edit the *config.yaml* or override on the command line:
> >
> > ~~~
> > $ snakemake -j1 -pf --config replicates=["2","3"] -- multiqc_out
> > ~~~
> >
> > Note that we need to re-run the final report, but only this, so only `-f` is necessary. If you find that
> > replicate 1 is still in you report, make sure you are using the final version of the *multiqc* rule from the
> > previous episode, that symlinks the inputs into a *multiqc_in* directory.
> >
> {: .solution}
{: .challenge}

{% include links.md %}