library(shiny)
library(shinydashboard)
library(DT)
library(htmltools)
library(ggplot2)
library(dplyr)

stackedBarChart <- function(table, rows, cols, title, show.legend=F, legend.position="top") {
  # Note: drugLevels is a global variable
  table <- table %>%
    arrange(
      #factor(databaseDescription, levels = rev(databaseList$databaseDescription)),
      factor(group, levels=rev(drugLevels))
    ) %>%
    mutate(
      #databaseDescription=factor(databaseDescription, levels=rev(databaseList$databaseDescription)),
      group=factor(group,levels=rev(drugLevels))
    )

  p <- ggplot(table, aes(fill=group, y=percentage, x=year)) + 
    geom_bar(position="fill", stat="identity", show.legend = show.legend) +
    drugLevelsColorBrew +
    labs(x = "Year", y = "Percentage (%)", title = title) +
    scale_y_continuous(labels=scales::percent) +
    guides(fill=guide_legend(title="Treatment"))
  
  if (show.legend) {
    p <- p + theme(legend.position = legend.position)
  }

  p <- p + facet_wrap(facets = vars(table$databaseDescription),
                      nrow=rows,
                      ncol=cols)
  return(p)
}

truncateStringDef <- function(columns, maxChars) {
  list(
    targets = columns,
    render = JS(sprintf("function(data, type, row, meta) {\n
      return type === 'display' && data != null && data.length > %s ?\n
        '<span title=\"' + data + '\">' + data.substr(0, %s) + '...</span>' : data;\n
     }", maxChars, maxChars))
  )
}

minCellCountDef <- function(columns) {
  list(
    targets = columns,
    render = JS("function(data, type) {
    if (type !== 'display' || isNaN(parseFloat(data))) return data;
    if (data >= 0) return data.toString().replace(/(\\d)(?=(\\d{3})+(?!\\d))/g, '$1,');
    return '<' + Math.abs(data).toString().replace(/(\\d)(?=(\\d{3})+(?!\\d))/g, '$1,');
  }")
  )
}

minCellPercentDef <- function(columns) {
  list(
    targets = columns,
    render = JS("function(data, type) {
    if (type !== 'display' || isNaN(parseFloat(data))) return data;
    if (data >= 0) return (100 * data).toFixed(1).replace(/(\\d)(?=(\\d{3})+(?!\\d))/g, '$1,') + '%';
    return '<' + Math.abs(100 * data).toFixed(1).replace(/(\\d)(?=(\\d{3})+(?!\\d))/g, '$1,') + '%';
  }")
  )
}

minCellRealDef <- function(columns, digits = 1) {
  list(
    targets = columns,
    render = JS(sprintf("function(data, type) {
    if (type !== 'display' || isNaN(parseFloat(data))) return data;
    if (data >= 0) return data.toFixed(%s).replace(/(\\d)(?=(\\d{3})+(?!\\d))/g, '$1,');
    return '<' + Math.abs(data).toFixed(%s).replace(/(\\d)(?=(\\d{3})+(?!\\d))/g, '$1,');
  }", digits, digits))
  )
}

styleAbsColorBar <- function(maxValue, colorPositive, colorNegative, angle = 90) {
  JS(sprintf("isNaN(parseFloat(value))? '' : 'linear-gradient(%fdeg, transparent ' + (%f - Math.abs(value))/%f * 100 + '%%, ' + (value > 0 ? '%s ' : '%s ') + (%f - Math.abs(value))/%f * 100 + '%%)'", 
             angle, maxValue, maxValue, colorPositive, colorNegative, maxValue, maxValue))
}

getCovariateDataSubset <- function(cohortId, databaseList, comparatorCohortId = NULL) {
  if (usingDbStorage()) {
    return(getCovariateValue(connPool, cohortId = cohortId, databaseList = databaseList, comparatorCohortId = comparatorCohortId))
  } else {
    return(covariateValue[covariateValue$cohortId %in% c(cohortId, comparatorCohortId) & covariateValue$databaseId %in% databaseList, ])
  }
}

getDataTableSettings <- function() {
  dtSettings <- list(
    options = list(pageLength = 25,
                   lengthMenu = c(25, 50, 100, -1),
                   searching = TRUE,
                   lengthChange = TRUE,
                   ordering = TRUE,
                   paging = TRUE,
                   info = TRUE,
                   scrollX = TRUE),
    extensions = list() #list('Buttons') #'RowGroup'
  )
                     
  return(dtSettings)
}

renderBorderTag <-  function() {
  return(htmltools::withTags(
    div(class="cohort-heading")
  ))
}

plotCpdSegmented <- function(Time, Samples, model_cpt, family) {
  # get n estimated cpts
  ncpts_est <- nrow(model_cpt$psi)  # one estimated cpt in one row
  
  # plot(model_cpt, conf.level=0.95, shade=TRUE,type = 'l', xlab = 'Month', ylab = 'N Drugs', main =
  # paste('Segmented Poisson Regression , ncpt =', ncpts = n, sep =' '), xaxt ='n')# plots regression
  # lines of the two segments using the coeffs returned in model_cpt
  plot(1:length(Time),
       Samples,
       xlab = "Month",
       ylab = "N Drugs",
       main = paste("Segmented", family, "Regression", sep = " "),
       xaxt = "n",
       cex = 1.5,
       pch = 16)  # add the actual time series, ,type = 'l'
  plot(model_cpt,
       add = TRUE,
       link = FALSE,
       lwd = 2,
       col = 3:5,
       lty = c(1, 1))  # added fitted line using diff cols for diff segments
  points(model_cpt, link = TRUE, col = 2)  # circle the brkpt
  lines(model_cpt, col = 2, pch = 19, bottom = FALSE, lwd = 2)  # add CI for the breakpoint
  
  # change xtick
  
  # mth_lab <- unlist(lapply(Time, month_name)) axis(1, at = Time, labels = mth_lab)
  axis(1, at = 1:length(Time), labels = Time)
  
  # get cpts
  cpts_initial <- model_cpt$psi[1:ncpts_est, 1]  # first column is the initial cpts, one cpt per row
  cpts_segmented <- model_cpt$psi[1:ncpts_est, 2]  # secnd column is the final   cpts, one cpt per row
  
  
  # plot cpts
  abline(v = cpts_initial, col = "grey", lwd = 3, lty = 2)  # plot the initial cpt in grey
  
  for (cp in 1:length(cpts_segmented)) {
    abline(v = cpts_segmented[cp], col = "red", lwd = 3, lty = 2)
  }  # add estimated cpts in red
}

shinyServer(function(input, output, session) {
  output$cohortCountsTable <- renderDataTable({
    databaseIds <- unique(cohortCount$databaseIds)
    table <- cohortCount[,c("cohortId", "name", "databaseId", "cohortSubjects", "cohortEntries")]
    names(table) <- c("Cohort ID", "Name", "Database", "Subjects", "Entries")

    # sketch <- htmltools::withTags(table(
    #   class = 'display',
    #   thead(
    #     tr(
    #       th(rowspan = 2, 'Cohort'),
    #       th(rowspan = 2, 'Strata'),
    #       lapply(databaseIds, th, colspan = 1, class = "dt-center")
    #     ),
    #     tr(
    #       lapply(rep(c("Subjects"), length(databaseIds)), th)
    #     )
    #   )
    # ))
    # 
    # sortCallback <- c(
    #   "var dt = table.table().node();",
    #   "$(dt).on('order.dt', function(e, ctx, order) {",
    #   "console.log(order);",
    #   " if (Array.isArray(order) && order.length > 0) {",
    #   "    console.log(order[0]);",
    #   "    col = order[0].col;",
    #   "    if (col < 2) {",
    #   "      var api = new $.fn.DataTable.Api(this);",
    #   "      var orderingArr = [];",
    #   "      for (var i=0 ; i<order.length ; i++) {",
    #   "        orderingArr.push(order[i].col);",
    #   "      }",
    #   #"      api.rowGroup().dataSrc(orderingArr);",
    #   "    }",
    #   "  }",
    #   "})"
    # )
    # columnDefs = list(
    #   #list(targets = c(0), visible = 0),
    #   minCellCountDef(2:(length(databaseIds) + 1))
    # )
    # dtSettings <- getDataTableSettings();
    # dtSettings$options <- append(dtSettings$options, list(columnDefs = columnDefs))
    
    dataTable <- datatable(table,
                           #callback = JS(sortCallback),
                           rownames = FALSE,
                           #container = sketch, 
                           #escape = FALSE,
                           #options = dtSettings$options,
                           #extensions = dtSettings$extensions,
                           class = "stripe nowrap compact")
    return(dataTable)    
  })
  
  output$tsPlot <- renderPlot({
    resultModel <- readRDS("data/linear_t1000_e2000_w1_cdm_optum_ehr_covid_v1547.rds")
    dexTrend <- trendsByMonthYear[trendsByMonthYear$cohortDefinitionId == 1000 & 
                                    trendsByMonthYear$eventCohortDefinitionId == 2000 &
                                    trendsByMonthYear$windowId == 1 & 
                                    trendsByMonthYear$databaseId == 'cdm_optum_ehr_covid_v1547',]
    dexTrend <- dexTrend[order(dexTrend$year, dexTrend$month), ]
    plotCpdSegmented(Samples = dexTrend$eventCount, 
                     Time = paste(dexTrend$year, dexTrend$month, sep="-"),  
                     model_cpt = resultModel[[1]]$models,
                     family = "linear")
  })
  
  # csDMARD Trends ---------------
  
  output$csDmardTrendTable <- renderDataTable({
    columnDefs <- list(
      minCellRealDef(c(3), 0)
    )
    dtSettings <- getDataTableSettings();
    dtSettings$options <- append(dtSettings$options, list(columnDefs = columnDefs))
    table <- dmardsByYear[, c("database", "year", "group","n")]
    colnames(table) <- c("Database", "Year", "Drug", "Count")
    table <- datatable(table,
                       rownames = FALSE,
                       escape = FALSE,
                       options = dtSettings$options,
                       extensions = dtSettings$extensions,
                       class = "stripe nowrap compact")
    return(table)
    
  })
  
  output$csDmardTrendPivotTable <- renderDataTable({
    columnsToInclude <- c("group", "year", "n","percentage")
    databaseIds <- unique(dmardsByYear$database)
    table <- dmardsByYear[dmardsByYear$database == databaseIds[1], columnsToInclude]
    colnames(table)[3] <- paste(colnames(table)[3], databaseIds[1], sep = "_")
    colnames(table)[4] <- paste(colnames(table)[4], databaseIds[1], sep = "_")
    if (length(databaseIds) > 1) {
      for (i in 2:length(databaseIds)) {
        temp <- dmardsByYear[dmardsByYear$database == databaseIds[i], columnsToInclude]
        colnames(temp)[3] <- paste(colnames(temp)[3], databaseIds[i], sep = "_")
        colnames(temp)[4] <- paste(colnames(temp)[4], databaseIds[i], sep = "_")
        table <- merge(table, temp, all = TRUE)
      }
    }
    
    createHeadings <- function(database) {
      return(list(
        tags$th(colspan = 1, paste0(database, "_cnt")),
        tags$th(colspan = 1, paste0(database, "_pct"))
      ))
    }
    
    sketch <- htmltools::withTags(table(
      class = 'display',
      thead(
        tr(
          th(rowspan = 2, 'Treatment'),
          th(rowspan = 2, 'Year'),
          lapply(databaseIds, th, colspan = 2, class = "dt-center no-border no-padding")
        ),
        tr(
          lapply(databaseIds, FUN = createHeadings)
        )
      )
    ))
    columnDefs <- list(
      minCellRealDef(seq(2, length(databaseIds)*2, by=2), 0),
      minCellPercentDef(seq(3, length(databaseIds)*2+1, by=2))
    )
    dtSettings <- getDataTableSettings();
    dtSettings$options <- append(dtSettings$options, list(columnDefs = columnDefs))
    table <- datatable(table,
                       rownames = FALSE,
                       container = sketch,
                       escape = FALSE,
                       options = dtSettings$options,
                       extensions = dtSettings$extensions,
                       class = "stripe nowrap compact")
    table <- formatStyle(table = table,
                         columns = 2:(length(databaseIds)*2)+1,
                         background = styleColorBar(c(0,2), "lightblue"),
                         backgroundSize = "98% 88%",
                         backgroundRepeat = "no-repeat",
                         backgroundPosition = "center")
    return(table)
  })
  
  output$csDmardTrendPlotUS <- renderPlot({
    usaPlot <- stackedBarChart(dmardsByYearAndDatabase[dmardsByYearAndDatabase$region == 'USA',], 2, 3, title="USA", T, legend.position = "top")
    return(usaPlot)
  }, res=100)
  
  output$csDmardTrendPlotEU <- renderPlot({
    eurPlot <- stackedBarChart(dmardsByYearAndDatabase[dmardsByYearAndDatabase$region == "Europe",], 2, 3, title="Europe", F)
    return(eurPlot)
    
  }, res=100)

  output$csDmardTrendPlotAP <- renderPlot({
    apPlot <- stackedBarChart(dmardsByYearAndDatabase[dmardsByYearAndDatabase$region == "Asia Pacific",], 1, 3, title="Asia Pacific", T, legend.position = "bottom")
    return(apPlot)
  }, res=100)
  
  # csDMARD Total ---------------
  
  output$csDmardTotalTable <- renderDataTable({
    columnDefs <- list(
      minCellRealDef(c(2,4), 0),
      minCellPercentDef(c(3))
    )
    dtSettings <- getDataTableSettings();
    dtSettings$options <- append(dtSettings$options, list(columnDefs = columnDefs))
    table <- dmardsTotal[, c("database","drug","count","pct","total")]
    colnames(table) <- c("Database", "Drug", "Treated", "% Treated", "Total RA Patients")
    table <- datatable(table,
                       rownames = FALSE,
                       escape = FALSE,
                       options = dtSettings$options,
                       extensions = dtSettings$extensions,
                       class = "stripe nowrap compact")
    return(table)
  })
  
  output$csDmardPivotTable <- renderDataTable({
    columnsToInclude <- c("drug","count","pct")
    databaseIds <- unique(dmardsTotal$database)
    databaseIdsWithCounts <- unique(dmardsTotal[,c("database","total")])
    table <- dmardsTotal[dmardsTotal$database == databaseIdsWithCounts$database[1], columnsToInclude]
    colnames(table)[2] <- paste(colnames(table)[2], databaseIdsWithCounts$database[1], sep = "_")
    colnames(table)[3] <- paste(colnames(table)[3], databaseIdsWithCounts$database[1], sep = "_")
    if (nrow(databaseIdsWithCounts) > 1) {
      for (i in 2:nrow(databaseIdsWithCounts)) {
        temp <- dmardsTotal[dmardsTotal$database == databaseIdsWithCounts$database[i], columnsToInclude]
        colnames(temp)[2] <- paste(colnames(temp)[2], databaseIdsWithCounts$database[i], sep = "_")
        colnames(temp)[3] <- paste(colnames(temp)[3], databaseIdsWithCounts$database[i], sep = "_")
        table <- merge(table, temp, all = TRUE)
      }
    }

    createHeadings <- function(database) {
      return(list(
        tags$th(colspan = 1, paste0(database, "_cnt")),
        tags$th(colspan = 1, paste0(database, "_pct"))
      ))
    }
    
    sketch <- htmltools::withTags(table(
      class = 'display',
      thead(
        tr(
          th(rowspan = 3, 'Treatment'),
          lapply(databaseIdsWithCounts$database, th, colspan = 2, class = "dt-center no-border no-padding")
        ),
        tr(
          lapply(paste0("(n = ", format(databaseIdsWithCounts$total, big.mark = ","), ")"), th, colspan = 2, class = "dt-center no-padding")
        ),
        tr(
          lapply(databaseIdsWithCounts$database, FUN = createHeadings)
        )
      )
    ))
    columnDefs <- list(
      minCellRealDef(seq(1, nrow(databaseIdsWithCounts)*2, by=2), 0),
      minCellPercentDef(seq(2, nrow(databaseIdsWithCounts)*2, by=2))
    )
    dtSettings <- getDataTableSettings();
    dtSettings$options <- append(dtSettings$options, list(columnDefs = columnDefs))
    table <- datatable(table,
                       rownames = FALSE,
                       container = sketch,
                       escape = FALSE,
                       options = dtSettings$options,
                       extensions = dtSettings$extensions,
                       class = "stripe nowrap compact")
    table <- formatStyle(table = table,
                         columns = 1:(nrow(databaseIdsWithCounts)*2)+1,
                         background = styleColorBar(c(0,1), "lightblue"),
                         backgroundSize = "98% 88%",
                         backgroundRepeat = "no-repeat",
                         backgroundPosition = "center")
    return(table)
  })
  
  output$csDmardTotalPlot <- renderPlot({
    table <- merge(dmardsTotal, databaseList, by.x="database", by.y="databaseId")
    # Sort the table 
    table <- table %>% 
      arrange(
        factor(databaseDescription, levels = rev(databaseList$databaseDescription)),
        factor(drug, levels=rev(drugLevels))
      ) %>%
      mutate(
        databaseDescription=factor(databaseDescription, levels=rev(databaseList$databaseDescription)),
        drug=factor(drug,levels=rev(drugLevels))
      )
    g <- ggplot(table, aes(x=databaseDescription, y=pctFormatted, fill=drug))
    posterColour <- "#21425A"
    textColour <- element_text(colour = posterColour)
    axisLine <- element_line(colour = posterColour)
    posterTheme <-   theme_classic(
      base_size = 16, 
      base_family = "sans",
    )+
      theme(text = textColour, 
            axis.title.x = textColour,
            axis.title.y = textColour,
            axis.text = textColour,
            axis.line = axisLine)
    
    f1 <- g +  
      geom_bar(stat = "identity") + 
      posterTheme +
      drugLevelsColorBrew+
      xlab("Real-world Health Care Databases")+
      ylab("Most Common First-line DMARD Regimens (%)")+
      labs(fill = "Treatment")+
      coord_flip()+
      guides(fill = guide_legend(reverse=T))
    return(f1)
  }, res = 100)
  
  # Database Info ------------------
  output$borderDatabaseInformation <- renderUI({
    return(renderBorderTag())
  })
  
  output$databaseInformationTable <- renderDataTable({

    table <- database #database[, c("databaseId", "databaseName", "description", "termsOfUse")]
    options = list(pageLength = 25,
                   searching = TRUE,
                   lengthChange = FALSE,
                   ordering = TRUE,
                   paging = FALSE#,
                   #columnDefs = list(list(width = '10%', targets = 0),
                    #                 list(width = '20%', targets = 1),
                    #                 list(width = '35%', targets = 2))
    )
    table <- datatable(table,
                       options = options,
                       #colnames = c("ID", "Name", "Description", "Terms of Use"),
                       rownames = FALSE,
                       class = "stripe compact")
    return(table)
  })
  
  output$dlDatabaseInformation <- downloadHandler(
    filename = function() {
      "database_info.csv"
    },
    content = function(file) {
      table <- database[, c("databaseId", "databaseName", "description")]
      write.csv(table, file, row.names = FALSE, na = "")
    }
  )
})
