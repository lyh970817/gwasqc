#!/bin/bash -l
#SBATCH --mem=256000 --ntasks=1 --nodes=1

#job control error
set -m

##Set-up for new users
#conda activate Bioresource - for new R (and tidyverse). See the yaml file in the scripts folder.
#export PATH="/users/k1184869/.conda/envs/bioresource_env/lib/R:${PATH}" - for Rscript
#module load r/4.1.1-gcc-9.4.0-withx-rmath-standalone-python-3.8.12   # - R for Ollie's pipeline
module load r/4.3.0-gcc-13.2.0-withx-rmath-standalone-python3+-chk-version

#Required packages for Ollie's Pipeline
#optargs
#library(data.table)
#library(caret)
#library(pROC)
#library(verification)
#library(ggplot2)
#library(cowplot)
#MLmetrics
#glmnet

#CREATE examples:
#sbatch -p cpu /scratch/prj/bioresource/Scripts/02.qc/full_pipe.sh -d /scratch/prj/bioresource/data/GLAD/02.pre_qc/GLADb08b09b12b16b17 -p /scratch/prj/bioresource/Scripts/02.qc -n GLAD_test -o /scratch/prj/bioresource/data/pipe_test/
#bash /scratch/prj/bioresource/Scripts/02.qc/full_pipe.sh -d /scratch/prj/bioresource/data/GLAD/02.pre_qc/GLADb08b09b12b16b17 -p /scratch/prj/bioresource/Scripts/02.qc -n GLAD_test -o /scratch/prj/bioresource/data/pipe_test/
#bash /scratch/prj/bioresource/Scripts/02.qc/full_pipe.sh -d /scratch/prj/bioresource/data/GLAD/02.pre_qc/GLADb08b09b12b16b17 -p /scratch/prj/bioresource/Scripts/02.qc -n GLAD_options -o /scratch/prj/bioresource/data/pipe_test/ --maf 0.05 --hwe 0.000000005 --geno 0.02 --mind 0.02

: <<'END'

#Add these as variables in your terminal to run default options and easily copy and paste a line in this script for testing.
path=/scratch/prj/bioresource/Scripts/02.qc
name=GLAD_test
maf=0.01
SNP_CR=95
Sample_CR=95
geno=0.05
mind=0.05
hwe=0.0000000001
plink=/scratch/users/k1184869/plink1.9/plink
plink2=/scratch/users/k1184869/plink2/plink2

END

##TO DO##
#add variable for hwe name? hwe with dot and zeros is clunky in a file name.
#1kg files need to be in path directory along with scripts (re-do for Ollie's pipeline)
#make final summary file automatically _/
#Add error when no inputs are given _/
#Add PCA plots
#Check for redundant make beds
#Add build 38 flag (new & old!)
#Build 38 checker tool? check specific variants exist in specific positions
#Sort out sed numbers correspond to correct lines in finalreport.log (removed sed _/)
#Update bash options to use full-word flags _/
#Time and date don't work with SBATCH
#Locating script for defaults doesn't work with SBATCH


#Change from using make-bed to snplists
#Add plink2 file path option _/

#Help function
function Help(){
   # Display Help
   echo "############################################"
   echo "### BioResource Genetic QC Pipeline Help ###"
   echo "############################################"
   echo
   echo "This program accepts plink files and should be used after the pre-qc batch merging phase."
   echo "It is designed for build 38 of the Human Reference Genome."
   echo
   echo "The intended use of this pipeline is to first run using the default QC settings and generate the output tables and graphs."
   echo "Using this information, located in the QC_pipeline_review_documents folder, rerun the pipeline with QC thresholds bespoke to the data used."
   echo
   echo "--data is the only required argument, but running without a path, name, or output location will generate a warning message."
   echo
   echo "Syntax: full_pipe.sh [-d <data> p|n|o|h|P|m|g|i|e|b|q|v|V]"
   echo "Options:"
   echo "d | data       Input plink file set."
   echo "p | path       Directory containing scripts and 1kg files. Note lower case p."
   echo "n | name       Study name e.g. GLADv3, GLADv3_eur."
   echo "o | out        Optional (recommended) output filepath e.g. /mnt/lustre/groups/bioresource/data/GLAD. No trailing '/'. Default is the location of this script."
   echo "h | help       Print this Help."
   echo "P | plink)     Plink 1.9 software file path (default: users/k1929222/programs/plink). Note upper case P."
   echo "m | maf)       Minor allele frequency threshold"
   echo "L | SNP_CR)    SNP call rates threshold"
   echo "I | Sample_CR) Sample call rates threshold"
   echo "g | geno)      Missing variant threshold (decimal)"
   echo "i | mind)      Missing individual threshold (decimal)"
   echo "e | hwe)       Hardy-weinberg equilibrium threshold"
   echo "b | ibd)       Pairwise identical-by-descent threshold"
   echo "q | ind_ibd)   Individual IBD outlier, standard deviations"
   echo "v              Verbose mode."
   echo "V              Print version and exit."
   echo
}

# Ensures that the number of passed args are at least equal
# to the declared number of mandatory args.
# It also considers -h or --help args.
function margs_precheck {
	if [ $2 ] && [ $1 -lt $margs ]; then
		if [ $2 == "--help" ] || [ $2 == "-h" ]; then
      Help
			exit
		else
        echo "ERROR: Too few arguments passed to the pipeline script."
        echo " "
	    	Help
	    	exit 1 # error
		fi
	fi
}

# Ensures that all the mandatory args are not empty
function margs_check {
	if [ $# -lt $margs ]; then
      echo " "
      echo "ERROR: Please ensure that mandatory arguments are not empty"
      echo " "
      Help
	    exit 1 # error
	fi
}
############################################################
# Pipeline                                                 #
############################################################

script="full_pipe.sh"
#rundate=$(date +"%d-%m-%Y_%k-%M-%S")
rundate="$(date +'%d-%m-%Y_%H-%M-%S')"
rundate2=$(date)

# check if script is started via SLURM or bash
# if with SLURM: there variable '$SLURM_JOB_ID' will exist
# `if [ -n $SLURM_JOB_ID ]` checks if $SLURM_JOB_ID is not an empty string
if [ -n $SLURM_JOB_ID ];  then
    # check the original location through scontrol and $SLURM_JOB_ID
    SCRIPT_PATH=$(scontrol show job $SLURM_JOBID | awk -F= '/Command=/{print $2}')
else
    # otherwise: started with bash. Get the real location.
    SCRIPT_PATH="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
fi

#Declare the number of mandatory args
margs=1
margs_precheck $# $1

#Initialise variables
data=  #input plink file
path=  #scripts directory
name=  #study name e.g. GLADv3, GLADv3_eur
out=   #Output file path
plink=
maf=
SNP_CR=
Sample_CR=
geno=
mind=
hwe=
ibd=
ind_ibd=
verbose="false"


# Args while-loop
while [ "$1" != "" ];
do
   case $1 in
   -d  | --data )  shift
                data=$1
                echo "Using input data:" $data
                		;;
   -p  | --path )  shift
   						  path=$1
                echo "Locating scripts from path directory: $path"
			              ;;
   -n  | --name )  shift
                name=$1
                echo "Study name: $name"
                    ;;
   -o  | --out )  shift
                out=$1
                echo "Output directory: $out"
                 		;;
   -P | --plink ) shift # plink file path
                plink=$1
                echo "Plink directory: $plink"
                    ;;
        --plink2 ) shift # plink2 file path
                plink2=$1
                echo "Plink2 directory: $plink2"
                    ;;
   -m | --maf ) shift # minor allele frequency threshold
                maf=$1
                echo "Minor Allele Frequency Threshold: $maf"
                    ;;
   -L | --SNP_CR ) shift # SNP call rate threshold
                SNP_CR=$1
                echo "SNP Call rate: $SNP_CR"
                    ;;
   -I | --Sample_CR ) shift # Sample call rate threshold
                Sample_CR=$1
                echo "Sample Call rate: $Sample_CR"
                    ;;
   -g | --geno ) shift # missing variant threshold
                geno=$1
                echo "Variant Missingness Threshold(geno): $geno"
                    ;;
   -i | --mind ) shift # missing individual threshold
                mind=$1
                echo "Individual Missingness Threshold(mind): $mind"
                    ;;
   -w | --hwe ) shift # hardy-weinberg equilibrium threshold
                hwe=$1
                echo "Hardy-Weinberg Equilibrium Threshold: $hwe"
                    ;;
   -b | --ibd ) shift # identical by descent
                ibd=$1
                echo "Pairwise identical-by-descent threshold: $ibd"
                    ;;
   -q | --ind_ibd ) shift # individual ibd outlier, standard deviation
                ind_ibd=$1
                echo "Individual IBD, Standard Deviations: $ind_ibd"
                    ;;
   -v | --verbose ) shift # verbose
                verbose="true"
                echo "Verbose: $verbose"
                    ;;
   -V | --version ) shift # version
                echo "Version Number 1.0"
                exit
                    ;;
   -h   | --help )
                Help
                exit
                    ;;
   *)
                echo "$script: Error: Invalid option $1."
                echo "Use -h to show help."
						    exit 1 # error
                    ;;
    esac
    shift
done

# Pass mandatory args to checking function
margs_check $data

#Adding defaults for required variables that are unspecified (and a warning needs to be shown)
#Path
if [ -z "${path}" ]
then
  path=$SCRIPT_PATH
  echo "WARNING: No path directory entered. Using script directory as default: $path"
  echo "Use -h option for usage notes"
  echo " "
fi

#Name
if [ -z "${name}" ]
then
  name=BR_QC_${rundate}
  echo "WARNING: study name unspecified. Using default name: BR_QC_${rundate} "
  echo "Use -h option for usage notes"
  echo " "
fi

#Out
if [ -z "${out}" ]
then
  out=$SCRIPT_PATH
  echo "WARNING: No output directory entered. Using script directory as default: $out"
  echo "Use -h option for usage notes"
  echo " "
  cd $out
fi



#Add Programs
#module add r/4.1.1-gcc-9.4.0-withx-rmath-standalone-python-3.8.12
#module add plink/1.9-beta6.10-gcc-9.4.0
#module add plink/1.9-beta6.10-gcc-13.2.0

if plink=""
  then plink=plink
  echo "Using default Plink location"
fi

if plink2=""
  then plink2=/scratch/users/k1184869/plink2/plink2
  echo "Using default Plink2 location"
fi

echo "Creating directory structure in $out"

mkdir -p ${out}/${name}_${rundate}
cd ${out}/${name}_${rundate}
out=$(pwd)
mkdir ./QC_pipeline_review_documents_${name}

echo "----------------------------------------------------------------------------------------------------" >> ${name}_finalreport.log
echo "Performing Genotype QC Pipeline for ${name}. Pipeline run on ${rundate2}" >> ${name}_finalreport.log
echo "----------------------------------------------------------------------------------------------------" >> ${name}_finalreport.log
echo " "

echo "###########################################"
echo "### BioResource Genetic QC Pipeline v1.0 ###"
echo "###########################################"
echo " "

##Apply MAF cutoff
$plink --bfile $data --allow-extra-chr --maf ${maf:=0.01} --make-bed --out ${name}_maf${maf}

echo "Applying MAF cutoff of ${maf}" >> ${name}_finalreport.log
grep "variants removed" ${name}_maf${maf}.log >> ${name}_finalreport.log
grep "people pass filters and QC." ${name}_maf${maf}.log >> ${name}_finalreport.log
echo " " >> ${name}_finalreport.log

## Check missingness
$plink --bfile ${name}_maf${maf} --allow-extra-chr --missing --hardy --make-bed --out ${name}_maf${maf}_check

Rscript ${path}/missingness_histograms.r ${name}_maf${maf}_check.lmiss $name $out

mv missingness_hist*${name}* ./QC_pipeline_review_documents_${name}/

## Run iterative missingness 0.90-0.99
sh ${path}/Iterative_Missingness.sh 90 99 1 ${name}_maf${maf}_check

#From each log file, collect the number of variants/individuals removed using that threshold
#Get first log value
grep removed ${name}_maf${maf}_check.common_SNP*.log | tr -d ' variants removed due to missing genotype data (--geno).' > geno90_int.txt

#Get every other geno/mind log value
sed -n '/removed/p' ${name}_maf${maf}_check.common_sample*.SNP*.log | tr -d ' <a-z>(--).' > otherlogs_int.txt

#Concatenate these text files
cat geno90_int.txt otherlogs_int.txt > logvalues_int.txt

#Get alternate columns for geno/mind values
sed 'N;s/\n/ /' logvalues_int.txt > split_cols_int.txt

#Select relevent column (geno/mind) and add 0s to every other row
awk 'BEGIN { FS=" " }; {print $1}' split_cols_int.txt | sed '2,$s/^/0\n/' > geno0_int.txt #note that geno is the first operation in it_miss plink script, so 0s are placed from line 2, and a trailing 0 is added.
echo "0" >> geno0_int.txt
awk 'BEGIN { FS=" " }; {print $2}' split_cols_int.txt | sed "s/^/0\n/" > mind0_int.txt

#rejoin files
paste geno0_int.txt mind0_int.txt > genomind_int.txt

#Add sample/snp threshold column
sample_snp_array=(90 90/90 90/91 91/91 91/92 92/92 92/93 93/93 93/94 94/94 94/95 95/95 95/96 96/96 96/97 97/97 97/98 98/98 98/99 99/99)
printf '%s\n' "${sample_snp_array[@]}" > samplesnp_int.txt
paste samplesnp_int.txt genomind_int.txt > 3col_genomind_int.txt

#add column names
awk 'BEGIN { OFS="\t"; print "Sample/SNP\t" "Variants\t" "Participants"}; { print $0 }' 3col_genomind_int.txt > Iterative_missingness_table_${name}.txt

#remove intermediate files
rm *_int.txt

#Make nice table
Rscript ${path}/itmiss_table.r ${name}

mv itmiss_table_${name}* ./QC_pipeline_review_documents_${name}/

#Default: Moving forward at 95% cutoff for variants and participants
#check this - can do geno and mind together?
$plink --bfile ${name}_maf${maf}_check.common_sample${Sample_CR:=95}.SNP${SNP_CR:=95} --allow-extra-chr --make-bed --out ${name}_maf${maf}_sample${Sample_CR:=95}.SNP${SNP_CR:=95}
#$plink --bfile ${name}_maf${maf} --allow-extra-chr --geno ${SNP_CR:=0.05} --make-bed --out ${name}_maf${maf}.SNP${SNP_CR}
#$plink --bfile ${name}_maf${maf}.SNP${SNP_CR} --allow-extra-chr --mind ${Sample_CR:=0.05} --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}

#Report no. of remaining individuals and variants
echo "Applying ${SNP_CR} cutoff for variants and ${Sample_CR} cutoff for individuals" >> ${name}_finalreport.log
grep "people pass filters and QC." ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.log >> ${name}_finalreport.log
grep "ERROR" ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.log >> ${name}_finalreport.log
echo " " >> ${name}_finalreport.log

#remove intermediate iterative missingness files
rm ./${name}_maf${maf}_check.common_*.log
rm ./${name}_maf${maf}_check.common_*.bed
rm ./${name}_maf${maf}_check.common_*.bim
rm ./${name}_maf${maf}_check.common_*.fam
rm ./${name}_maf${maf}_check.common_*.hh


#Hardy-Weinberg checks
$plink --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR} --allow-extra-chr --hardy --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}_hardycheck

#Plot hardy
Rscript ${path}/hardy_plots.r ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}_hardycheck.hwe $name $out

mv hardy_*${name}* ./QC_pipeline_review_documents_${name}

#Apply cutoff (default 10^-10)
$plink --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR} --allow-extra-chr --hwe ${hwe:=0.0000000001} --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}

echo "Applying Hardy cutoff of ${hwe}" >> ${name}_finalreport.log
grep "variants removed" ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.log >> ${name}_finalreport.log
grep "people pass filters and QC." ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.log >> ${name}_finalreport.log
echo " " >> ${name}_finalreport.log

####LD Pruning####
$plink --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}  --allow-extra-chr --indep-pairwise 1500 150 0.2 --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pre

## Extract prune.in
$plink --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe} --allow-extra-chr --extract ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pre.prune.in --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned

echo "LD pruning dataset: window size = 1500kb; step size (variant ct) = 150; r^2 threshold = 0.2" >> ${name}_finalreport.log
grep "people pass filters and QC." ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned.log >> ${name}_finalreport.log
echo " " >> ${name}_finalreport.log

## Make highLDregion and Autosomalexcludes SNP file
awk -f $path/highLDregions4bim_b38.awk ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned.bim > highLDexcludes
awk '($1 < 1) || ($1 > 22) {print $2}' ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned.bim > autosomeexcludes
cat highLDexcludes autosomeexcludes > highLD_and_autosomal_excludes

### Exclude highLDregion and Autosomalexcludes SNPs
$plink --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned --allow-extra-chr --exclude highLD_and_autosomal_excludes --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr

echo "Excluding highLDregion and Autosomalexcludes SNPs within pruned data" >> ${name}_finalreport.log
grep "people pass filters and QC." ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr.log >> ${name}_finalreport.log
echo " " >> ${name}_finalreport.log

#running sex check
$plink --allow-extra-chr --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned --split-x 'no-fail' b38 --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_split_x

$plink --allow-extra-chr --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_split_x --check-sex ycount --set-hh-missing --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_sexcheck
--

Rscript ${path}/sex_check_hist.r ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_sexcheck.sexcheck ${name} ${out}

mv sexcheck_hist_${name}* ./QC_pipeline_review_documents_${name}
mv sexcheck_hist_y20_${name}* ./QC_pipeline_review_documents_${name}

#Extract rows with sex discrepancies and export to a table
grep PROBLEM ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_sexcheck.sexcheck > sexmismatch_${name}.txt

#Get length of sexmismatch.txt and report number or discrepancies
sex_mismatch_count=$(wc -l < sexmismatch_${name}.txt)
echo "Number of sex discrepancies: ${sex_mismatch_count}" >> ${name}_finalreport.log
echo " " >> ${name}_finalreport.log


mv sexmismatch_${name}.txt ./QC_pipeline_review_documents_${name}

#Remove sex mismatches (manual check)


###Heterozygosity Check

$plink --allow-extra-chr --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr --ibc --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr_Hetcheck

Rscript ${path}/het_graphs.r ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr_Hetcheck.ibc ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_sexcheck.sexcheck ${name}

mv Het_check_hist_${name}.pdf ./QC_pipeline_review_documents_${name}
mv HetFhat2_SexF_${name}.pdf ./QC_pipeline_review_documents_${name}

###Cryptic relatedness

#Pairwise identical-by-descent (IBD) check

$plink --bfile ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr --allow-extra-chr --genome --make-bed --out ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr.IBD

## Check >9 Pi_Hat individuals: duplicates or twins
awk '$10 > 0.9 {print $0}' ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr.IBD.genome > pihat_over_9_${name}.txt
## Check 0.4 < $10 < 0.6 Pi_Hat individuals: family
awk '$10 > 0.4 && $10 < 0.6 {print $0}' ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr.IBD.genome > pihat_btw_4_6_${name}.txt

#Count of pairs without headers
let twinpair_count=$(wc -l < pihat_over_9_${name}.txt)-1
sibparent_count=$(wc -l < pihat_btw_4_6_${name}.txt)

echo "There are ${twinpair_count} number of twins/duplicate pairs." >> ${name}_finalreport.log
echo "There are ${sibparent_count} number of siblings/parent-offspring pairs." >> ${name}_finalreport.log

#Add call rate info to pihat outputs
#Get header
awk 'NR<2 {print $0 }' pihat_over_9_${name}.txt > pihat_over_9_${name}_header.txt

#Add Call Rate (F_MISS) to header
echo "     F_MISS_1     F_MISS_2" > extra_header.txt
paste pihat_over_9_${name}_header.txt extra_header.txt > callrate_pihat_over_9_${name}_header.txt

#Sort and join pihat and call rate files
join -1 1 -2 1 -o 1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11,1.12,1.13,1.14,2.6 <(sort -k1 pihat_over_9_${name}.txt) <(sort -k1 ${name}_maf${maf}_check.imiss) > callrate1_pihat_over_9_${name}.txt
join -1 3 -2 1 -o 1.1,1.2,1.3,1.4,1.5,1.6,1.7,1.8,1.9,1.10,1.11,1.12,1.13,1.14,1.15,2.6 <(sort -k3 callrate1_pihat_over_9_${name}.txt) <(sort -k1 ${name}_maf${maf}_check.imiss) > callrate2_pihat_over_9_${name}.txt
sort -k1 callrate2_pihat_over_9_${name}.txt > callrate3_pihat_over_9_${name}.txt

#Attach new header
cat callrate_pihat_over_9_${name}_header.txt callrate3_pihat_over_9_${name}.txt > callrate_pihat_over_9_${name}.txt

#move pihat/call rate file to review folder
mv callrate_pihat_over_9_${name}.txt ./QC_pipeline_review_documents_${name}

echo "" >> ${name}_finalreport.log
echo "Manually review phenotypic data of IDs in callrate_pihat_over_9_${name}.txt to determine whether they are twins or duplicates." >> ${name}_finalreport.log
echo "If determined to be a duplicate, remove one with higher F_MISS value (Higher missingness/lower call rate)" >> ${name}_finalreport.log
echo "" >> ${name}_finalreport.log

#remove intermediate callrate files
rm ./extra_header.txt
rm ./callrate1_pihat_over_9_${name}.txt
rm ./callrate2_pihat_over_9_${name}.txt
rm ./callrate3_pihat_over_9_${name}.txt

#Remove one sample from each pair with pi-hat (% IBD) above threshold (0.1875 default)
awk -v ibd="${ibd:=0.1875}" '$10 >= ibd {print $1, $2}' ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr.IBD.genome > ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr.IBD_outliers.txt

wait

#Remove outliers here?

#Calculate average IBD per individual using R, output outliers (defined as more than sigma standard deviations above the mean, as provided by the user)

## Individual-level average PI_Hat
R --file=${path}/IndividualIBD.r --args ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr ${ind_ibd:=3}

mv ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr.IBD_INDIV_outliers.txt ./QC_pipeline_review_documents_${name}


#Plot all IBD Histograms
Rscript ${path}/IBD_Hist.r ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr ${name}

#Plot Individual IBD outlier Histograms
Rscript ${path}/IndvIBD_Hist.r ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe}.LD_Pruned_autosomalchr ${name}

mv *_${name}.pdf ./QC_pipeline_review_documents_${name}

###Ancestry check

#Run Ancestry Identifier Pipeline (full 1kg data)
Rscript ${path}/ancestry_identifier.r \
  --target_plink ${name}_maf${maf}_sample${Sample_CR}.SNP${SNP_CR}.hwe${hwe} \
  --ref_plink_chr ${path}/ref/1kg/1KG_Phase3.chr \
  --n_pcs 10 \
  --maf $maf \
  --geno 0.02 \
  --hwe 0.000001 \
  --plink $plink \
  --plink2 $plink2 \
  --output $name \
  --ref_pop_scale $path/ref/1kg/ref_super_pop_keep_list.txt \
  --pop_data $path/ref/1kg/ref_pop_dat_reduced.txt \
  --prob_thresh 0.5

#Rename Ancestry pipeline log to ${name}_ancestry_identifier.log
mv ${name}.log ${name}_ancestry_identifier.log

#Add to relevent sections to the final report
echo "" >> ${name}_finalreport.log
echo "Ancestry identification complete. PCA plots available in ${name}.PCs_plot_super_pop.png." >> ${name}_finalreport.log
echo "" >> ${name}_finalreport.log

grep -A6  'N per group based on model:' ${name}_ancestry_identifier.log >> ${name}_finalreport.log
echo "" >> ${name}_finalreport.log
grep -A6  'N per group based on 3SD rule:' ${name}_ancestry_identifier.log >> ${name}_finalreport.log
echo "" >> ${name}_finalreport.log

#Move files to review folder
mv ${name}.PCs_plot_super_pop.png ./QC_pipeline_review_documents_${name}
mv ${name}_ancestry_identifier.log ./QC_pipeline_review_documents_${name}

mv ${name}_finalreport.log ./QC_pipeline_review_documents_${name}
exit
