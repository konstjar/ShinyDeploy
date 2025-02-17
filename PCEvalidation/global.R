# uncomment if running standalone
##runPlp <- readRDS(file.path("data","results.rds"))
##validatePlp <- readRDS(file.path("data","extValidation.rds"))
source("processing.R")

if(is.null(.GlobalEnv$shinySettings$result)){
  result <- 'data'
  print('Extracting results from data folder')
} else{
  result <- .GlobalEnv$shinySettings$result
  print('Extracting results from .GlobalEnv$shinySettings')
}

if(is.null(.GlobalEnv$shinySettings$validation)){
  validation <- NULL
} else{
  validation <- .GlobalEnv$shinySettings$validation
}

inputType <- checkPlpInput(result) # this function checks 
if(!class(validation)%in%c('NULL', 'validatePlp')){
  stop('Incorrect validation class')
}
if(inputType == 'file' & !is.null(validation)){
  warning('Validation input ignored when result is a directory location')
}

summaryTable <- getSummary(result, inputType, validation)


myResultList <- lapply(1:nrow(summaryTable), function(i){paste('Val:',as.character(summaryTable$Val[i]),
                                                                 '-T:', as.character(summaryTable$T[i]),
                                                               '- O:',as.character(summaryTable$O[i]),
                                                               '- TAR:', as.character(summaryTable$TAR[i]),
                                                               '- Model:', as.character(summaryTable$Model[i]),
                                                               'Predictor:', as.character(summaryTable$covariateSettingId[i]))})


getTable1 <- function(tn='Persons who are statin-risk eligible'){
  if(file.exists('data/table1.csv')){
    tab1 <- read.csv('data/table1.csv')
    tab1 <- tab1[tab1$targetName==tn,colnames(tab1)!='X']
  } else{
    tab1 <- NULL
  }
  return(tab1)
}

myCohortList <- list('Persons who are statin-risk eligible',
                     'Non-Black Female Persons who are statin-risk eligible', 
                     'Non-Black Male Persons who are statin-risk eligible')

# Non-Black Female Persons who are statin-risk eligible, Non-Black Male Persons who are statin-risk eligible