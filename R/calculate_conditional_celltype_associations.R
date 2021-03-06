#' Calculate conditional celltype associations using MAGMA
#'
#' Assumes that you have already run map.snps.to.genes()
#'
#' @param ctd Cell type data strucutre containing $quantiles
#' @param gwas_sumstats_path Filepath of the summary statistics file
#' @param analysis_name Used in filenames which area created
#' @param upstream_kb How many kb upstream of the gene should SNPs be included?
#' @param downstream_kb How many kb downstream of the gene should SNPs be included?
#' @param genome_ref_path Path to the folder containing the 1000 genomes .bed files (which can be downloaded from https://ctg.cncr.nl/software/MAGMA/ref_data/g1000_eur.zip)
#' @param specificity_species Species name relevant to the cell type data, i.e. "mouse" or "human"
#' @param controlledAnnotLevel Which annotation level should be controlled for
#' @param controlTopNcells How many of the most significant cell types at that annotation level should be controlled for?
#'
#' @return Filepath for the genes.out file
#'
#' @examples
#' ctAssocs = calculate_celltype_associations(ctd,gwas_sumstats_path)
#'
#' @export
calculate_conditional_celltype_associations <- function(ctd,gwas_sumstats_path,analysis_name="MainRun",upstream_kb=10,downstream_kb=1.5,genome_ref_path,controlledAnnotLevel=1,specificity_species="mouse",controlTopNcells=2){
    gwas_sumstats_path = path.expand(gwas_sumstats_path)
    #sumstatsPrefix = sprintf("%s.%sUP.%sDOWN",gwas_sumstats_path,upstream_kb,downstream_kb)
    magmaPaths = get.magma.paths(gwas_sumstats_path,upstream_kb,downstream_kb)
    
    # Check for errors in arguments
    check_inputs_to_magma_celltype_analysis(ctd,gwas_sumstats_path,analysis_name,upstream_kb,downstream_kb,genome_ref_path)
    
    # Calculate the baseline associations
    ctAssocs = calculate_celltype_associations(ctd,gwas_sumstats_path,genome_ref_path=genome_ref_path,specificity_species=specificity_species,EnrichmentMode = EnrichmentMode)
    
    # Find the cells which are most significant at baseline at controlled annotation level
    res = ctAssocs[[controlledAnnotLevel]]$results
    res = res[order(res$P),]
    signifCells = as.character(res[res$P<(0.05/ctAssocs$total_baseline_tests_performed),"Celltype"])
    
    if(length(signifCells)>controlTopNcells){
        signifCells = signifCells[1:controlTopNcells]
    }
    
    # If there are no significant cells... then stop
    if(length(signifCells)==0){stop("No celltypes reach significance with Q<0.05")}
    
    # Create gene covar file for the controlled for annotation level
    controlledCovarFile = create_gene_covar_file(genesOutFile = sprintf("%s.genes.out",magmaPaths$filePathPrefix),ctd,controlledAnnotLevel,specificity_species=specificity_species)
    # Read in the controlled Covar File
    controlledCovarData = read.table(controlledCovarFile,stringsAsFactors = FALSE,header=TRUE)
    #colnames(controlledCovarData)[2:length(colnames(controlledCovarData))] = colnames(ctd[[controlledAnnotLevel]]$quantiles)
    transliterateMap = data.frame(original=colnames(ctd[[controlledAnnotLevel]]$quantiles),modified=colnames(controlledCovarData)[2:length(colnames(controlledCovarData))],stringsAsFactors = FALSE)
    signifCells2 = transliterateMap[transliterateMap$original %in% signifCells,]$modified # Because full stops replace spaces when the covars are written to file... (and MAGMA sees spaces as delimiters)
    controlledCovarCols = controlledCovarData[,c("entrez",signifCells2)]
    
    for(annotLevel in 1:length(ctd)){
        count=allRes=0
        
        # First match quantiles to the genes in the genes.out file... then write as the genesCovar file (the input to MAGMA)
        genesCovarFile = create_gene_covar_file(genesOutFile = sprintf("%s.genes.out",magmaPaths$filePathPrefix),ctd,annotLevel,specificity_species=specificity_species)
        
        for(controlFor in signifCells2){
            if(annotLevel!=controlledAnnotLevel){
                genesCovarData = read.table(genesCovarFile,stringsAsFactors = FALSE,header=TRUE)
                genesCovarData2 = merge(genesCovarData,controlledCovarCols[,c("entrez",controlFor)])
                write.table(genesCovarData2,file=genesCovarFile,quote=FALSE,row.names=FALSE,sep="\t")
            }
            
            sumstatsPrefix2 = sprintf("%s.level%s.%sUP.%sDOWN.ControlFor_%s",magmaPaths$filePathPrefix,annotLevel,upstream_kb,downstream_kb,controlFor)
            #magma_cmd = sprintf("magma --gene-results '%s.genes.raw' --gene-covar '%s' onesided condition='%s' --out '%s'",magmaPaths$filePathPrefix,genesCovarFile,controlFor,sumstatsPrefix2)
            
            print(magma_cmd)
            system(magma_cmd)    
            
            cond_res = load.magma.results.file(path=sprintf("%s.gcov.out",sumstatsPrefix2),annotLevel,ctd,genesOutCOND=NA,EnrichmentMode="Linear",ControlForCT=controlFor)
            count = count + 1
            if(count==1){
                allRes = cond_res
            }else{
                allRes = rbind(allRes,cond_res)
            }
        }
        ctAssocs[[annotLevel]]$results = rbind(ctAssocs[[annotLevel]]$results,allRes)
    }
    
    # Calculate total number of tests performed
    totalTests = 0
    for(annotLevel in 1:sum(names(ctAssocs)=="")){
        totalTests = totalTests + dim(ctAssocs[[annotLevel]]$results)[1]
    }
    ctAssocs$total_conditional_tests_performed = totalTests
    
    ctAssocs$gwas_sumstats_path = gwas_sumstats_path
    ctAssocs$analysis_name = analysis_name
    ctAssocs$upstream_kb = upstream_kb
    ctAssocs$downstream_kb = downstream_kb
    ctAssocs$genome_ref_path = genome_ref_path    
    
    return(ctAssocs)
}