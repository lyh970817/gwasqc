#!/bin/bash -l
#SBATCH --cpus-per-task=15
#SBATCH --ntasks=1
#SBATCH --nodes=1
#SBATCH --partition=cpu
#SBATCH --mem-per-cpu=19000



cd /scratch/prj/nihr_ukbiobank/GLAD/02.pre_QC_rw/New_pre_QC/Merge_GLAD_NBR

# If writing to the same file, parallel should be run on only one node

module add parallel
module add bcftools
module add plink/1.9-beta6.10-gcc-10.3.0


# Check build

#vcfs=($(echo *.vcf.gz))
#vcfs_base=($(for v in ${vcfs[@]}; do echo ${v%.vcf.gz}; done))

# parallel '[[zless {}|head|grep "reference=Hg38"]] || lftover'

# Convert VCF files into binary files
#parallel --link plink --vcf {1} --allow-extra-chr  \
#	 --make-bed --out {2} \
#	::: ${vcfs[@]} ::: ${vcfs_base[@]}

# Extract Variant IDs and INFO/RSID from VCF files
#function extract_id() {
#	bcftools query -f'[%ID %INFO/RSID\n]' $1 | sort -u |
#	awk '$2=="." {print $1, $1;next} {print $1, $2}' >Rec_var_$2.update
#}

#export -f extract_id

#parallel --link 'extract_id {1} {2}' \
#	::: ${vcfs[@]} ::: ${vcfs_base[@]} &

#wait

# Remove lab controls

#parallel --link plink --bfile {} --allow-extra-chr --remove remove.txt  --make-bed --out {}_exl ::: ${vcfs_base[@]}

# Update sex
#parallel --link plink -bfile {}_exl --allow-extra-chr \
#	--update-sex update_fam_gender.txt --make-bed --out {}_exl_sex ::: ${vcfs_base[@]}


# Update rsIDs and [FI]IDs
#parallel plink --bfile {}_exl_sex \
#	--update-name Rec_var_{}.update --update-ids {}.update_id \
#	--allow-extra-chr --make-bed --out {}_exl_sex_rsid \
#	::: ${vcfs_base[@]}

vcfs=($(echo *.bim))
vcfs_base=($(for v in ${vcfs[@]}; do echo ${v%.bim}; done))


# Combine all bim files and get unique combinations of all columns
parallel "awk -v file="{}" '{print \$0, file}'" {}.bim \
	::: ${vcfs_base[@]} | sort -uk 1,6 >all.bim

#find a position having different alleles--> collect different rsIDs on the position from all.bim

# Get rsids of later (not first) duplicates
# (Should) deal with inconsistent chr&pos as well as alleles
# awk 'dup_rs[$2]++||dup_chrpos[$1"_"$4]++' all.bim >snps.exclude
awk 'dup_chrpos[$1"_"$4]++{print $1,$4}' all.bim | sort -u > position.exclude
awk -F' ' 'NR==FNR{c[$1$2]++;next};c[$1$4] > 0' position.exclude all.bim | awk '{print $2}' > snps.exclude

#awk 'dup_rs[$2]++||dup_chrpos[$2"_"$1"_"$4]++' all.bim >snps.exclude
#awk 'dup_rs[$2]++||(dup_rschrpos[$2"_"$1"_"$4]++&&dup_chrpos[$1"_"$4]++)' all.bim >snps.exclude

# swapped alleles better lmiss?

# Exlucde duplicated snps (including originals)
parallel plink --bfile {} --exclude snps.exclude \
	--allow-extra-chr --make-bed --out {}_exl \
	::: ${vcfs_base[@]}

# Combine all fam files. Add a "file" column for splitting later
parallel "awk -v file="{}_exl" '{print \$0, file}'" {}_exl.fam ::: ${vcfs_base[@]} >all_rs.fam

# Recode duplicated ids with different iid
# Concerns with manually modifying fam files: fam linked with bed by row index
awk 'ids[$2]++{$2=sprintf("%s_%s", $2, ids[$2])} {print}' all_rs.fam >tmp &&
	mv tmp all_rs.fam

function extract_batch() {
	awk -v file="$1" '$7==file' all_rs.fam \
	>"$1.fam"
}
export -f extract_batch

# Separate the "all" fam file
parallel 'extract_batch {}_exl' ::: ${vcfs_base[@]}

# Merge all batches

printf "%s\n" "${vcfs_base[@]}" | xargs -I{} printf "%s%s\n" {} "_exl" > merge_list


plink --merge-list merge_list --allow-extra-chr \
	--merge-equal-pos --make-bed --out all_rs

# To go to QC
# # Lower nmiss on top, so remove the rest
# sort -r -k 2,2 -k 4,4 all_rs.imiss | awk 'ids[$2]++{print $1, $2}' >nmiss.remove
# plink2 --bfile all_rs --remove nmiss.remove --make-bed --out all_rs

# # Make fids and iids the same
# awk '{$1=$2;print}' all_rs.bim >tmp && mv all_rs.fam


