# Copyright 2022 Observational Health Data Sciences and Informatics
#
# This file is part of CohortDiagnostics
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


loadResultsTable <- function(dataSource, tableName, required = FALSE, tablePrefix = "") {
  selectTableName <- paste0(tablePrefix, tableName)

  resultsTablesOnServer <-
    tolower(DatabaseConnector::dbListTables(dataSource$connection, schema = dataSource$resultsDatabaseSchema))

  if (required || selectTableName %in% resultsTablesOnServer) {
    tryCatch(
    {
      table <- DatabaseConnector::dbReadTable(
        dataSource$connection,
        paste(dataSource$resultsDatabaseSchema, selectTableName, sep = ".")
      )
    },
      error = function(err) {
        stop(
          "Error reading from ",
          paste(dataSource$resultsDatabaseSchema, selectTableName, sep = "."),
          ": ",
          err$message
        )
      }
    )
    colnames(table) <-
      SqlRender::snakeCaseToCamelCase(colnames(table))
    if (nrow(table) > 0) {
      return(dplyr::as_tibble(table))
    }
  }

  return(NULL)
}


# Create empty objects in memory for all other tables. This is used by the Shiny app to decide what tabs to show:
tableIsEmpty <- function(dataSource, tableName) {
  sql <-
    sprintf(
      "SELECT 1 FROM %s.%s LIMIT 1;",
      dataSource$resultsDatabaseSchema,
      tableName
    )
  oneRow <- DatabaseConnector::dbGetQuery(dataSource$connection, sql)
  return(nrow(oneRow) == 0)
}

getTimeAsInteger <- function(time = Sys.time()) {
  return(floor(as.numeric(as.POSIXlt(time))))
}

getTimeFromInteger <- function(x) {
  originDate <- as.POSIXct("1970-01-01")
  originDate <- originDate + x
  return(originDate)
}

processMetadata <- function(data) {
  data <- data %>%
    tidyr::pivot_wider(
      id_cols = c(.data$startTime, .data$databaseId),
      names_from = .data$variableField,
      values_from = .data$valueField
    ) %>%
    dplyr::mutate(
      startTime = stringr::str_replace(
        string = .data$startTime,
        pattern = stringr::fixed("TM_"),
        replacement = ""
      )
    ) %>%
    dplyr::mutate(startTime = paste0(.data$startTime, " ", .data$timeZone)) %>%
    dplyr::mutate(startTime = as.POSIXct(.data$startTime)) %>%
    dplyr::group_by(
      .data$databaseId,
      .data$startTime
    ) %>%
    dplyr::arrange(.data$databaseId, dplyr::desc(.data$startTime), .by_group = TRUE) %>%
    dplyr::mutate(rn = dplyr::row_number()) %>%
    dplyr::filter(.data$rn == 1) %>%
    dplyr::select(-.data$timeZone)

  if ("runTime" %in% colnames(data)) {
    data$runTime <- round(x = as.numeric(data$runTime), digits = 2)
  }
  if ("observationPeriodMinDate" %in% colnames(data)) {
    data$observationPeriodMinDate <-
      as.Date(data$observationPeriodMinDate)
  }
  if ("observationPeriodMaxDate" %in% colnames(data)) {
    data$observationPeriodMaxDate <-
      as.Date(data$observationPeriodMaxDate)
  }
  if ("personsInDatasource" %in% colnames(data)) {
    data$personsInDatasource <- as.numeric(data$personsInDatasource)
  }
  if ("recordsInDatasource" %in% colnames(data)) {
    data$recordsInDatasource <- as.numeric(data$recordsInDatasource)
  }
  if ("personDaysInDatasource" %in% colnames(data)) {
    data$personDaysInDatasource <-
      as.numeric(data$personDaysInDatasource)
  }
  colnamesOfInterest <-
    c(
      "startTime",
      "databaseId",
      "runTime",
      "runTimeUnits",
      "sourceReleaseDate",
      "cdmVersion",
      "cdmReleaseDate",
      "observationPeriodMinDate",
      "observationPeriodMaxDate",
      "personsInDatasource",
      "recordsInDatasource",
      "personDaysInDatasource"
    )

  commonColNames <- intersect(colnames(data), colnamesOfInterest)

  data <- data %>%
    dplyr::select(dplyr::all_of(commonColNames))
  return(data)
}

checkErrorCohortIdsDatabaseIds <- function(errorMessage,
                                           cohortIds,
                                           databaseIds) {
  checkmate::assertDouble(
    x = cohortIds,
    null.ok = FALSE,
    lower = 1,
    upper = 2^53,
    any.missing = FALSE,
    add = errorMessage
  )
  checkmate::assertCharacter(
    x = databaseIds,
    min.len = 1,
    any.missing = FALSE,
    unique = TRUE,
    add = errorMessage
  )
  checkmate::reportAssertions(collection = errorMessage)
  return(errorMessage)
}

quoteLiterals <- function(x) {
  if (is.null(x)) {
    return("")
  } else {
    return(paste0("'", paste(x, collapse = "', '"), "'"))
  }
}

getConnectionPool <- function(connectionDetails) {
  connectionPool <-
    pool::dbPool(
      drv = DatabaseConnector::DatabaseConnectorDriver(),
      dbms = connectionDetails$dbms,
      server = connectionDetails$server(),
      port = connectionDetails$port(),
      user = connectionDetails$user(),
      password = connectionDetails$password(),
      connectionString = connectionDetails$connectionString()
    )

  return(connectionPool)
}

loadShinySettings <- function(configPath) {
  stopifnot(file.exists(configPath))
  shinySettings <- yaml::read_yaml(configPath)

  if (is.null(shinySettings$connectionDetails$server)) {
    shinySettings$connectionDetails$server <-
      paste0(Sys.getenv("phenotypeLibraryServer"),
             "/",
             Sys.getenv("phenotypeLibrarydb"))
  }
  
  if (is.null(shinySettings$connectionDetails$user)) {
    shinySettings$connectionDetails$user <-
      Sys.getenv("phenotypeLibrarydbUser")
  }
  
  if (is.null(shinySettings$connectionDetails$password)) {
    shinySettings$connectionDetails$password <-
      Sys.getenv("phenotypeLibrarydbPw")
  }

  defaultValues <- list(
    resultsDatabaseSchema = c("main"),
    vocabularyDatabaseSchemas = c("main"),
    enableAnnotation = TRUE,
    enableAuthorization = TRUE,
    userCredentialsFile = "UserCredentials.csv",
    tablePrefix = "",
    cohortTableName = "cohort",
    databaseTableName = "database"
  )

  for (key in names(defaultValues)) {
    if (is.null(shinySettings[[key]])) {
      shinySettings[[key]] <- defaultValues[[key]]
    }
  }

  if (shinySettings$cohortTableName == "cohort") {
    shinySettings$cohortTableName <- paste0(shinySettings$tablePrefix, shinySettings$cohortTableName)
  }

  if (shinySettings$databaseTableName == "database") {
    shinySettings$databaseTableName <- paste0(shinySettings$tablePrefix, shinySettings$databaseTableName)
  }


  if (!is.null(shinySettings$connectionDetailsSecureKey)) {
    shinySettings$connectionDetails <- jsonlite::fromJSON(keyring::key_get(shinySettings$connectionDetailsSecureKey))
  }
  shinySettings$connectionDetails <- do.call(DatabaseConnector::createConnectionDetails,
                                             shinySettings$connectionDetails)

  return(shinySettings)
}

createDatabaseDataSource <- function(connection,
                                     resultsDatabaseSchema,
                                     vocabularyDatabaseSchema = resultsDatabaseSchema,
                                     dbms,
                                     tablePrefix = "",
                                     cohortTableName = "cohort",
                                     databaseTableName = "database") {
  return(
    list(
      connection = connection,
      resultsDatabaseSchema = resultsDatabaseSchema,
      vocabularyDatabaseSchema = vocabularyDatabaseSchema,
      dbms = dbms,
      resultsTablesOnServer = tolower(DatabaseConnector::dbListTables(connection, schema = resultsDatabaseSchema)),
      tablePrefix = tablePrefix,
      prefixTable = function(tableName) { paste0(tablePrefix, tableName) },
      prefixVocabTable = function(tableName) {
        # don't prexfix table if we us a dedicated vocabulary schema
        if (vocabularyDatabaseSchema == resultsDatabaseSchema)
          return(paste0(tablePrefix, tableName))

        return(tableName)
      },
      cohortTableName = cohortTableName,
      databaseTableName = databaseTableName
    )
  )
}

#' Initialize variables required in applications global shared environment
#' These settings are shared across settings (e.g. accessed by all users) and should be read only during run time
initializeEnvironment <- function(shinySettings,
                                  table1SpecPath = "data/Table1SpecsLong.csv",
                                  dataModelSpecificationsPath = "data/resultsDataModelSpecification.csv",
                                  envir = .GlobalEnv) {
  envir$shinySettings <- shinySettings

  envir$connectionPool <- getConnectionPool(envir$shinySettings$connectionDetails)
  shiny::onStop(function() {
    if (DBI::dbIsValid(envir$connectionPool)) {
      writeLines("Closing database pool")
      pool::poolClose(envir$connectionPool)
    }
  })

  envir$dataSource <-
    createDatabaseDataSource(
      connection = envir$connectionPool,
      resultsDatabaseSchema = envir$shinySettings$resultsDatabaseSchema,
      vocabularyDatabaseSchema = envir$
        shinySettings$
        vocabularyDatabaseSchemas,
      dbms = envir$shinySettings$connectionDetails$dbms,
      tablePrefix = envir$shinySettings$tablePrefix,
      cohortTableName = envir$shinySettings$cohortTableName,
      databaseTableName = envir$shinySettings$databaseTableName
    )

  envir$userCredentials <- data.frame()
  envir$enableAuthorization <- envir$shinySettings$enableAuthorization
  if (is.null(envir$enableAuthorization)) {
    envir$enableAuthorization <- FALSE
  }

  if (envir$enableAuthorization & !is.null(envir$shinySettings$userCredentialsFile)) {
    if (file.exists(envir$shinySettings$userCredentialsFile)) {
      envir$userCredentials <-
        readr::read_csv(file = envir$shinySettings$userCredentialsFile, col_types = readr::cols())
    }
  }

  envir$enableAnnotation  <- envir$shinySettings$enableAnnotation

  if (nrow(envir$userCredentials) == 0) {
    envir$enableAuthorization <- FALSE
  }

  dataModelSpecifications <- read.csv(dataModelSpecificationsPath)
  envir$dataModelSpecifications <- dataModelSpecifications
  # Cleaning up any tables alreadu in memory:
  suppressWarnings(rm(
    list = SqlRender::snakeCaseToCamelCase(envir$dataModelSpecifications$tableName),
    envir = envir
  ))

  envir$database <- loadResultsTable(envir$dataSource, envir$dataSource$databaseTableName, required = TRUE)
  envir$cohort <- loadResultsTable(envir$dataSource, envir$dataSource$cohortTableName, required = TRUE)
  envir$metadata <- loadResultsTable(envir$dataSource, "metadata", required = TRUE, tablePrefix = envir$dataSource$tablePrefix)
  envir$temporalTimeRef <- loadResultsTable(envir$dataSource, "temporal_time_ref", tablePrefix = envir$dataSource$tablePrefix)
  envir$temporalAnalysisRef <- loadResultsTable(envir$dataSource, "temporal_analysis_ref", tablePrefix = envir$dataSource$tablePrefix)
  envir$conceptSets <- loadResultsTable(envir$dataSource, "concept_sets", tablePrefix = envir$dataSource$tablePrefix)
  envir$cohortCount <- loadResultsTable(envir$dataSource, "cohort_count", required = TRUE, tablePrefix = envir$dataSource$tablePrefix)
  envir$relationship <- loadResultsTable(envir$dataSource, "relationship", tablePrefix = envir$dataSource$tablePrefix)


  if (is.numeric(envir$database$databaseId)) {
    envir$metadata$databaseId <- as.numeric(envir$metadata$databaseId)
  }

  if (!is.null(envir$cohort)) {
    if ("cohortDefinitionId" %in% names(envir$cohort)) {
      envir$cohort <- envir$cohort %>% dplyr::mutate(cohortId = .data$cohortDefinitionId)

      ## Note this is because the tables were labled wrong!
      envir$cohort <- envir$cohort %>% dplyr::mutate(cohortId = .data$cohortDefinitionId,
                                                     sql = .data$json,
                                                     json = .data$sqlCommand)
    }

    envir$cohort <- envir$cohort %>%
      dplyr::arrange(.data$cohortId) %>%
      dplyr::mutate(shortName = paste0("C", .data$cohortId)) %>%
      dplyr::mutate(compoundName = paste0(.data$shortName, ": ", .data$cohortName))
  }

  if (!is.null(envir$database)) {
    if (nrow(envir$database) > 0 &
      "vocabularyVersion" %in% colnames(envir$database)) {
      envir$database <- envir$database %>%
        dplyr::mutate(
          databaseIdWithVocabularyVersion = paste0(.data$databaseId, " (", .data$vocabularyVersion, ")")
        )
    }

    envir$databaseMetadata <- processMetadata(envir$metadata)
    envir$databaseMetadata <- envir$database %>%
      dplyr::distinct() %>%
      dplyr::mutate(id = dplyr::row_number()) %>%
      dplyr::mutate(shortName = paste0("D", .data$id)) %>%
      dplyr::left_join(envir$databaseMetadata,
                       by = "databaseId"
      ) %>%
      dplyr::relocate(.data$id, .data$databaseId, .data$shortName)


    if ("databaseName" %in% names(envir$database)) {
      envir$dbMapping <- envir$database %>%
        dplyr::select(.data$databaseId, .data$databaseName) %>%
        dplyr::distinct()
    } else {
      envir$dbMapping <- envir$database %>%
        dplyr::select(.data$databaseId, .data$cdmSourceName) %>%
        dplyr::distinct() %>%
        dplyr::mutate(databaseName = .data$cdmSourceName)
    }
  }

  envir$temporalChoices <- NULL
  envir$temporalCharacterizationTimeIdChoices <- NULL

  if (!is.null(envir$temporalTimeRef)) {
    envir$temporalChoices <- getResultsTemporalTimeRef(dataSource = envir$dataSource)
    envir$temporalCharacterizationTimeIdChoices <- envir$temporalChoices %>%
      dplyr::arrange(.data$sequence)

    envir$characterizationTimeIdChoices <- envir$temporalChoices %>%
      dplyr::filter(.data$isTemporal == 0) %>%
      dplyr::filter(.data$primaryTimeId == 1) %>%
      dplyr::arrange(.data$sequence)
  }

  if (!is.null(envir$temporalAnalysisRef)) {
    
    cohortAnalysisRef <-
      dplyr::bind_rows(
        dplyr::tibble(
          analysisName = c(
            "c1:precedes (p)",
            "c1:meets (m)",
            "c1:overlaps (o)",
            "c1:finished by (F)",
            "c1:contains (D)",
            "c1:starts (s)",
            "c1:equals (e)",
            "c1:started by (S)",
            "c1:during (d)",
            "c1:finishes (f)",
            "c1:overlapped by (O)",
            "c1:met by (M)",
            "c1:preceded by (P)"
          ),
          analysisId = c(-1:-13)
        ),
        dplyr::tibble(
          analysisName = c(
            "c2:endsIn (osd)",
            "c2:startsWithStart (seS)",
            "c2:startsIn (dfO)",
            "c2:endsWithEnd (Fef)",
            "c2:startsBeforeStart (pmoFD)",
            "c2:startsAfterStart (dfOMP)",
            "c2:startsBeforeEnd",
            "c2:endsBeforeEnd (pmoFDseSd)",
            "c2:endsAfterEnd (DSOMP)",
            "c2:startsInInclusive (seSdfOM)",
            "c2:endsInInclusive (oFsedf)",
            "c2:startsOnOrBeforeStart (pmoFDseS)",
            "c2:startsOnOrBeforeEnd (pmoFDseSdfoM)",
            "c2:endsOnOrBeforeEnd (pmoFsedf)",
            "c2:duringInclusive (esdf)"
          ),
          analysisId = c(-101:-115)
        )
      ) %>%
      dplyr::mutate(domainId = "Cohort",
                    isBinary = "Y",
                    missingMeansZero = "Y")
    
    envir$temporalAnalysisRef <- dplyr::bind_rows(
      envir$temporalAnalysisRef,
      cohortAnalysisRef
    )

    envir$domainIdOptions <- envir$temporalAnalysisRef %>%
      dplyr::select(.data$domainId) %>%
      dplyr::pull(.data$domainId) %>%
      unique() %>%
      sort()
    envir$analysisNameOptions <- envir$temporalAnalysisRef %>%
      dplyr::select(.data$analysisName) %>%
      dplyr::pull(.data$analysisName) %>%
      unique() %>%
      sort()
  }
  
  if (!is.null(envir$conceptSets)) {
    envir$conceptSets <- envir$conceptSets %>% 
      dplyr::mutate(compositeConceptSetName = paste0("C",
                                                     .data$cohortId,
                                                     ": ", 
                                                     .data$conceptSetName,
                                                     " (",
                                                     .data$conceptSetId,
                                                     ")")) %>% 
      dplyr::arrange(.data$cohortId,
                     .data$conceptSetName,
                     .data$conceptSetId)
  }

  envir$resultsTables <- tolower(DatabaseConnector::dbListTables(dataSource$connection,
                                                                 schema = dataSource$resultsDatabaseSchema))
  envir$enabledTabs <- c()
  for (table in envir$dataModelSpecifications$tableName %>% unique()) {
    if (envir$dataSource$prefixTable(table) %in% envir$resultsTables) {
      if (!tableIsEmpty(envir$dataSource, envir$dataSource$prefixTable(table))) {
        envir$enabledTabs <- c(envir$enabledTabs, SqlRender::snakeCaseToCamelCase(table))
      }
    }
  }

  if (!(envir$dataSource$cohortTableName %in% envir$resultsTables & envir$dataSource$databaseTableName %in% envir$resultsTables)) {
    stop(paste("cohort table:", envir$dataSource$cohortTableName, "and database table:", envir$dataSource$databaseTableName, "must be in results schema"))
  }

  envir$enabledTabs <- c(envir$enabledTabs, "database", "cohort")

  envir$prettyTable1Specifications <- readr::read_csv(
    file = table1SpecPath,
    col_types = readr::cols(),
    guess_max = min(1e7),
    lazy = FALSE
  )

  envir$analysisIdInCohortCharacterization <- c(
    1, 3, 4, 5, 6, 7,
    203, 403, 501, 703,
    801, 901, 903, 904,
    -1:-13,
    -101:-115
  )

  envir$analysisIdInTemporalCharacterization <- c(
    101, 401, 501, 701,
    -1:-13,
    -101:-115
  )

  if (envir$enableAnnotation &
    "annotation" %in% envir$resultsTables &
    "annotation_link" %in% envir$resultsTables &
    "annotation_attributes" %in% envir$resultsTables) {
    envir$showAnnotation <- TRUE
    envir$enableAnnotation <- TRUE
  } else {
    envir$enableAnnotation <- FALSE
    envir$showAnnotation <- FALSE
    envir$enableAuthorization <- FALSE
  }

  return(envir)
}
