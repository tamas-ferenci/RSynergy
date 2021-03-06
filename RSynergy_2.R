library(data.table)

# We read the data for the combinations
RawDataComb <- data.table( rio::import( paste0( "https://mct.aacrjournals.org/highwire/filestream/53222/",
                                                "field_highwire_adjunct_files/3/156849_1_supp_1_w2lrww.xls" ),
                                        format = "xlsx", na = "NULL", .name_repair = "universal" ) )

# A little check on BatchIDs
RawDataComb[,.(length(unique(BatchID))),.(drugA_name,drugB_name,cell_line)][V1>1]
RawDataComb[,as.list(table(factor(BatchID,levels=1:3))),.(drugA_name,drugB_name,cell_line)]
xtabs(~Batch1+Batch2+Batch3,data=RawDataComb[,as.list(table(factor(BatchID,levels=1:3,labels=paste0("Batch",1:3)))),
                                             .(drugA_name,drugB_name,cell_line)])
# No combination can have three types at the same time. Thus, by excluding BatchID==3 (which is anyways described
# as "a partial repeat of selected drugs and served as a validation"), no combination will have two different batches.
# BatchID can be safely dropped (as there is no documentation on any difference between them).
RawDataComb <- RawDataComb[ BatchID!=3 ]

# Percentage inhibition will be needed later
RawDataComb$response <- 100-100*RawDataComb$X.X0

# We read the single agent-data
RawDataSingle <- data.table( rio::import( paste0( "https://mct.aacrjournals.org/highwire/filestream/53222/",
                                                  "field_highwire_adjunct_files/1/156849_1_supp_0_w2lh45.xlsx" ),
                                          format = "xlsx", na = "NULL", .name_repair = "universal" ) )
RawDataSingle$response <- 100-100*RawDataSingle$X.X0 # Percentage inhibition will be needed later
RawDataSingle$dose <- RawDataSingle$Drug_concentration..µM. # To simplify feeding data into synergyfinder

# These will be repeatedly needed, so calculate them a single time
RawDataSingleModels <- lapply( setNames(unique(RawDataSingle$drug_name), unique(RawDataSingle$drug_name)),
                               function(drug) lapply( setNames(unique(RawDataSingle$cell_line), unique(RawDataSingle$cell_line)),
                                                      function(cline) synergyfinder::FitDoseResponse(
                                                        RawDataSingle[drug_name==drug&cell_line==cline] ) ) )
# Calculating all synergy scores
res <- RawDataComb[ ,mean( synergyfinder::Loewe( as.matrix( dcast(.SD, drugA.Conc..µM.~drugB.Conc..µM., value.var = "response"),
                                                            rownames = 1 ),
                                                 drug.row.model = RawDataSingleModels[[drugA_name]][[cell_line]],
                                                 drug.col.model = RawDataSingleModels[[drugB_name]][[cell_line]] )[-1,-1] ),
                    .(drugA_name,drugB_name,cell_line) ]
names(res)[1:3] <- c( "drug_row", "drug_col", "cell.line" )

# Let's save the data so that later we can skip this time-consuming data preparation
saveRDS( res, "resRSynergy.dat" )

# We load those synergy scores that the group provided...
labels <- read.csv( "http://www.bioinf.jku.at/software/DeepSynergy/labels.csv" )
names( labels )[ 2:3 ] <- c( "drug_row", "drug_col" )

# ...and check how similar it is to our ones
plot( V1 ~ synergy, data = merge( res[ , .( drug_row=toupper(drugA_name), drug_col=toupper(drugB_name),
                                            cell_line=toupper(cell_line), V1 ) ], labels ) )
abline( 0, 1, col = "red" )

# Plot something like their Figure 1
lattice::levelplot( V1~factor(drug_row)+factor(drug_col), data = res[cell.line=="ZR751"],
                    scales = list( x = list( rot = 90 ) ), xlab = "", ylab = "", main = "ZR751" )

# Symmetrizing the original results (that will be better later anyway)
res2 <- rbind( res, res[, .( drug_row = drug_col, drug_col = drug_row, cell.line, V1 ) ] )

# The plot is now OK
lattice::levelplot( V1~factor(drug_row)+factor(drug_col), data = res2[cell.line=="ZR751"],
                    scales = list( x = list( rot = 90 ) ), xlab = "", ylab = "", main = "ZR751" )

# Let's now reproduce Figure 1 from the paper
ordrow <- (as.data.table(table(res2$drug_row)))[order(-N,V1)]$V1
ordcol <- (as.data.table(table(res2$drug_col)))[order(N,-V1)]$V1

lattice::levelplot( V1~(drug_row)+as.factor(drug_col),
                    data = res2[ , .( drug_row = factor( drug_row, ordrow ), drug_col = factor( drug_col, ordcol ),
                                      cell.line, V1 )][cell.line=="ZR751"],
                    scales = list( x = list( rot = 90 ) ), xlab = "", ylab = "", main = "ZR751",
                    col.regions = colorRampPalette(c("darkred","darkblue"))(1000))

# We now load the descriptors of the cell lines from ArrayExpress E-MTAB-3610, as described in the paper

CellLineData <- ArrayExpress::getAE( "E-MTAB-3610" )
CellLineData <- affy::ReadAffy( filenames = CellLineData$rawFiles[ match(
  read.AnnotatedDataFrame( CellLineData$sdrf )@data$Array.Data.File,CellLineData$rawFiles ) ],
  phenoData = CellLineData$sdrf,
  description = CellLineData$idf )
CellLineData <- CellLineData[ , toupper( gsub( "-", "", CellLineData@phenoData@data$Characteristics.cell.line. ) )%in%
                                unique( res$cell.line ) ]
# Only 28 is found from 39!!! (e.g. CAOV3)
CellLineData <- farms::qFarms( CellLineData )
CellLineData <- farms::INIcalls( CellLineData )
summary( CellLineData )
plot( CellLineData )
CellLineData <- farms::getI_Eset( CellLineData )

# We now load the descriptors of the drugs and the cell lines, as provided by the original group
download.file( "http://www.bioinf.jku.at/software/DeepSynergy/X.p.gz", "X.p.gz", mode = "wb" )
system( "gunzip X.p.gz" )

# First reticulate::py_install("pandas") is needed
pd <- reticulate::import("pandas")
RawFeatures <- pd$read_pickle( "X.p" )

# Innen lehet ugyanaz a normalizálást csinálni mint ők (normalize.ipynb, fent van nálunk), vagy lehet mást

# ...normalizálás...

# We can start the machine learning part

library(keras)

# ...gépi tanulás...

# ...egyéb ötletek a gépi tanulás után...
