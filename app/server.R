# =============================================================================
# File:    server.R
# Purpose: Defines the server-side logic of the Shiny app.
#          This is the "controller" layer — it reacts to user input, talks to
#          the database, and sends results back to the UI.
#
# Key Shiny concepts used here:
#   - observeEvent() : runs code when a specific input changes (e.g. button click)
#   - reactive()     : a cached expression that re-runs when its inputs change
#   - render*()      : functions that produce output (tables, plots, UI elements)
#   - req()          : stops execution silently if a value is missing/NULL/NA
# =============================================================================

server <- function(input, output, session) {

  # ---------------------------------------------------------------------------
  # SECTION 1: Log Entry tab — INSERT a new measurement
  # ---------------------------------------------------------------------------

  # observeEvent() listens for a single event: the submit button being clicked.
  # The code inside runs exactly once per click, not continuously like a reactive.
  observeEvent(input$submit, {

    # req() is Shiny's guard clause. If any of these values are missing, empty,
    # or NA, execution stops here and nothing is sent to the database.
    # This prevents partial or empty rows from being inserted.
    req(
      input$observed_date,
      input$observed_time,
      input$location,
      input$measurement_type,
      input$value,
      input$unit,
      input$observer
    )

    # Combine the separate date and time inputs into a single timestamp string,
    # then parse it as a POSIXct with UTC+2 timezone (Central European Summer Time).
    # TIMESTAMPTZ in PostgreSQL stores the timezone, so we must provide one.
    observed_at <- tryCatch(
      as.POSIXct(
        paste(input$observed_date, input$observed_time),
        format = "%Y-%m-%d %H:%M",
        tz     = "Europe/Zurich"  # adjust to your local timezone
      ),
      error = function(e) NULL  # if parsing fails, return NULL so req() below catches it
    )

    # Stop if the timestamp could not be parsed (e.g. user typed "99:99")
    req(!is.null(observed_at))

    # Wrap the INSERT in tryCatch so a database error shows a friendly message
    # rather than crashing the app or showing a cryptic R error to the user.
    result <- tryCatch({

      # dbExecute() runs a SQL statement that does not return rows (INSERT, UPDATE, DELETE).
      # We use parameterised queries (the $1, $2 ... placeholders with the `params` argument)
      # to prevent SQL injection — never paste user input directly into a SQL string.
      DBI::dbExecute(
        pool,
        "INSERT INTO measurements
           (observed_at, location, measurement_type, value, unit, observer, notes)
         VALUES ($1, $2, $3, $4, $5, $6, $7)",
        params = list(
          observed_at,
          trimws(input$location),           # trimws() removes accidental leading/trailing spaces
          input$measurement_type,
          input$value,
          trimws(input$unit),
          trimws(input$observer),
          if (nchar(trimws(input$notes)) > 0) trimws(input$notes) else NA  # store NULL if empty
        )
      )

      "success"  # return a status string so tryCatch knows it worked

    }, error = function(e) {
      paste("error:", conditionMessage(e))  # return the error message as a string
    })

    # Render feedback HTML into the uiOutput("submit_feedback") placeholder in ui.R
    output$submit_feedback <- renderUI({
      if (result == "success") {
        div(
          class = "alert alert-success",  # Bootstrap green success box
          icon("check-circle"), " Measurement saved successfully."
        )
      } else {
        div(
          class = "alert alert-danger",   # Bootstrap red error box
          icon("exclamation-triangle"), " Failed to save: ", result
        )
      }
    })

    # After a successful insert, reset the form fields so the user can log
    # the next measurement without manually clearing each input.
    if (result == "success") {
      updateNumericInput(session, "value", value = NA)
      updateTextAreaInput(session, "notes", value = "")
      updateTextInput(session, "observed_time", value = format(Sys.time(), "%H:%M"))
    }
  })

  # ---------------------------------------------------------------------------
  # SECTION 2: Browse Data tab — SELECT with filters
  # ---------------------------------------------------------------------------

  # reactive() creates a cached data frame that re-runs whenever filter inputs change.
  # Any render*() function that calls filtered_data() will automatically update too.
  # This is the core of Shiny's reactive programming model.
  filtered_data <- reactive({

    # Build a parameterised SQL query. We always filter by date range;
    # measurement type filter is added conditionally.
    if (input$filter_type == "All") {

      DBI::dbGetQuery(
        pool,
        "SELECT id, observed_at, location, measurement_type, value, unit, observer, notes
         FROM measurements
         WHERE observed_at::date BETWEEN $1 AND $2
         ORDER BY observed_at DESC",
        params = list(input$filter_dates[1], input$filter_dates[2])
      )

    } else {

      DBI::dbGetQuery(
        pool,
        "SELECT id, observed_at, location, measurement_type, value, unit, observer, notes
         FROM measurements
         WHERE observed_at::date BETWEEN $1 AND $2
           AND measurement_type = $3
         ORDER BY observed_at DESC",
        params = list(input$filter_dates[1], input$filter_dates[2], input$filter_type)
      )
    }
  })

  # Populate the measurement type dropdown dynamically from the database.
  # This runs once when the app starts (it is inside observe(), not observeEvent()).
  # If someone adds a new type via the Log Entry tab, a manual Refresh picks it up.
  observe({
    types <- DBI::dbGetQuery(
      pool,
      "SELECT DISTINCT measurement_type FROM measurements ORDER BY measurement_type"
    )
    updateSelectInput(session, "filter_type",
      choices  = c("All", types$measurement_type),
      selected = "All"
    )
  })

  # Refresh button re-triggers filtered_data() by invalidating a reactive timer.
  # We use reactiveVal to track a dummy counter — incrementing it forces a re-run.
  refresh_trigger <- reactiveVal(0)

  observeEvent(input$refresh, {
    refresh_trigger(refresh_trigger() + 1)  # increment to trigger reactive dependency
  })

  # Render the DT table. options() control pagination, column order, and appearance.
  output$measurements_table <- renderDT({

    refresh_trigger()  # declare dependency so Refresh button triggers a re-query

    df <- filtered_data()

    # Format the timestamp column for human readability before displaying
    df$observed_at <- format(as.POSIXct(df$observed_at), "%Y-%m-%d %H:%M")

    datatable(
      df,
      rownames  = FALSE,            # hide the row number column
      selection = "none",           # disable row selection (read-only table)
      options   = list(
        pageLength = 15,            # rows per page
        order      = list(0, "desc"), # sort by first column (observed_at) descending
        columnDefs = list(
          list(targets = 0, visible = FALSE)  # hide the id column from the user
        )
      ),
      colnames = c(
        "ID", "Observed at", "Location", "Type", "Value", "Unit", "Observer", "Notes"
      )
    )
  })

  # ---------------------------------------------------------------------------
  # SECTION 3: Stats tab — summary table and boxplot
  # ---------------------------------------------------------------------------

  # Query aggregated stats grouped by measurement type.
  # This reactive re-runs whenever filtered_data() changes (shared filter state).
  summary_data <- reactive({
    df <- filtered_data()
    if (nrow(df) == 0) return(data.frame())  # return empty frame gracefully

    # Use base R aggregate — no dplyr dependency needed for a simple group-by
    agg <- aggregate(value ~ measurement_type, data = df, FUN = function(x) {
      c(n    = length(x),
        mean  = round(mean(x),   2),
        min   = round(min(x),    2),
        max   = round(max(x),    2),
        sd    = round(sd(x),     2))
    })

    # aggregate() with multiple FUN outputs returns a matrix column; flatten it
    data.frame(
      Type  = agg$measurement_type,
      N     = agg$value[, "n"],
      Mean  = agg$value[, "mean"],
      Min   = agg$value[, "min"],
      Max   = agg$value[, "max"],
      SD    = agg$value[, "sd"]
    )
  })

  # Render the static summary table
  output$summary_table <- renderTable({
    req(nrow(summary_data()) > 0)
    summary_data()
  }, striped = TRUE, hover = TRUE, bordered = TRUE)

  # Render the ggplot2 boxplot.
  # A boxplot is ideal for this data: it shows median, spread, and outliers
  # per measurement type in a single compact chart.
  output$boxplot <- renderPlot({

    df <- filtered_data()
    req(nrow(df) > 0)  # do not attempt to plot an empty data frame

    ggplot(df, aes(x = measurement_type, y = value, fill = measurement_type)) +

      # geom_boxplot draws the box (IQR), whiskers, and outlier points
      geom_boxplot(outlier.shape = 21, outlier.size = 2, alpha = 0.7) +

      # geom_jitter overlays the individual data points so you can see sample size
      geom_jitter(width = 0.15, alpha = 0.4, size = 1.5) +

      # Labels
      labs(
        x     = "Measurement type",
        y     = "Value",
        fill  = "Type",
        title = "Distribution of measurements by type",
        caption = paste("Filtered date range:", input$filter_dates[1], "to", input$filter_dates[2])
      ) +

      # theme_minimal removes the grey background for a clean, publication-ready look
      theme_minimal(base_size = 13) +
      theme(legend.position = "none")  # legend is redundant since x-axis already labels types
  })
}
