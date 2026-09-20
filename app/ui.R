# =============================================================================
# File:    ui.R
# Purpose: Defines the user interface of the Shiny app.
#          Shiny separates the UI (what the user sees) from the server logic
#          (what happens when the user interacts). This file is the "view" layer.
#
# Layout:  navbarPage with three tabs:
#            1. Log Entry  — form to submit a new measurement
#            2. Browse Data — interactive, filterable table of all entries
#            3. Stats       — summary statistics and boxplot per measurement type
# =============================================================================

ui <- navbarPage(

  # Application title shown in the browser tab and the top navigation bar
  title = "shiny-k8s-lab | Field Measurement Logger",

  # ---------------------------------------------------------------------------
  # TAB 1: Log Entry
  # Users fill in a form and click Submit to INSERT a row into PostgreSQL.
  # ---------------------------------------------------------------------------
  tabPanel(
    title = "Log Entry",

    # sidebarLayout splits the tab into a narrow left panel (inputs) and a
    # wider right panel (output / feedback). This is the standard Shiny pattern
    # for data-entry forms.
    sidebarLayout(

      sidebarPanel(
        width = 4,

        h4("Record a new measurement"),
        hr(), # horizontal rule for visual separation

        # dateTimeInput is not available in base Shiny, so we use two inputs:
        # a date picker and a time text box. They are combined in server.R.
        dateInput(
          inputId = "observed_date",
          label   = "Date observed",
          value   = Sys.Date(),  # default to today
          format  = "yyyy-mm-dd"
        ),

        textInput(
          inputId     = "observed_time",
          label       = "Time observed (HH:MM)",
          value       = format(Sys.time(), "%H:%M"),
          placeholder = "e.g. 09:30"
        ),

        textInput(
          inputId     = "location",
          label       = "Location",
          placeholder = "e.g. Lake Constance - North Shore"
        ),

        # A dropdown of common measurement types keeps data consistent.
        # "Other" allows free entry to keep the form flexible.
        selectInput(
          inputId  = "measurement_type",
          label    = "Measurement type",
          choices  = c(
            "pH", "Temperature", "Dissolved Oxygen",
            "Turbidity", "Conductivity", "Other"
          ),
          selected = "pH"
        ),

        # Numeric input with no default so the user must enter a value
        numericInput(
          inputId = "value",
          label   = "Value",
          value   = NA,
          step    = 0.01  # allow decimal precision
        ),

        textInput(
          inputId     = "unit",
          label       = "Unit",
          placeholder = "e.g. °C, mg/L, NTU, µS/cm"
        ),

        textInput(
          inputId     = "observer",
          label       = "Observer",
          placeholder = "e.g. J. Theiler"
        ),

        # notes is optional (nullable in the DB), so no placeholder pressure
        textAreaInput(
          inputId = "notes",
          label   = "Notes (optional)",
          rows    = 3
        ),

        hr(),

        # The submit button triggers the INSERT in server.R via observeEvent()
        actionButton(
          inputId = "submit",
          label   = "Submit measurement",
          class   = "btn-primary btn-block"  # Bootstrap classes: blue, full-width
        ),

        # Feedback message shown after submission (success or error)
        # uiOutput lets server.R render dynamic HTML here
        br(),
        uiOutput("submit_feedback")
      ),

      # The main panel is intentionally left sparse on this tab —
      # a confirmation message after submit keeps focus on the form.
      mainPanel(
        width = 8,
        h4("How to use"),
        p("Fill in all required fields and click ", strong("Submit measurement"), "."),
        p("The entry will be saved to the PostgreSQL database immediately and will
           appear in the ", strong("Browse Data"), " tab.")
      )
    )
  ),

  # ---------------------------------------------------------------------------
  # TAB 2: Browse Data
  # Displays all rows from the measurements table in an interactive DT table.
  # Filters above the table allow narrowing by measurement type and date range.
  # ---------------------------------------------------------------------------
  tabPanel(
    title = "Browse Data",

    sidebarLayout(

      sidebarPanel(
        width = 3,

        h4("Filter"),
        hr(),

        # Filter by measurement type — "All" means no filter applied
        selectInput(
          inputId  = "filter_type",
          label    = "Measurement type",
          choices  = c("All"),   # server.R populates this dynamically from the DB
          selected = "All"
        ),

        # Filter by date range using two date pickers
        dateRangeInput(
          inputId = "filter_dates",
          label   = "Date range",
          start   = Sys.Date() - 30,  # default: last 30 days
          end     = Sys.Date()
        ),

        hr(),

        # Reload button — re-queries the DB, picking up any new rows
        actionButton(
          inputId = "refresh",
          label   = "Refresh table",
          class   = "btn-default btn-block"
        )
      ),

      mainPanel(
        width = 9,

        h4("All measurements"),

        # DTOutput renders the interactive DataTables table.
        # The actual data and options are set in server.R via renderDT().
        DTOutput("measurements_table")
      )
    )
  ),

  # ---------------------------------------------------------------------------
  # TAB 3: Stats
  # Shows per-measurement-type summary statistics and a ggplot2 boxplot.
  # This tab demonstrates the read/visualise pattern common in data science apps.
  # ---------------------------------------------------------------------------
  tabPanel(
    title = "Stats",

    fluidRow(

      # Summary table on the left
      column(
        width = 4,
        h4("Summary statistics"),
        p(em("Grouped by measurement type")),
        tableOutput("summary_table")  # base Shiny table (static, no JS needed)
      ),

      # Boxplot on the right — shows distribution per type
      column(
        width = 8,
        h4("Distribution by measurement type"),
        p(em("Each box represents one measurement type. Outliers shown as points.")),
        plotOutput("boxplot", height = "400px")
      )
    )
  )
)
