library(shiny)
library(auth0)

#
pool <- dbPool(
  drv = RMariaDB::MariaDB(),
  dbname = "fullsend",
  host = Sys.getenv("FULLSEND_HOST"),
  username = Sys.getenv("FULLSEND_USER"),
  password = Sys.getenv("FULLSEND_PASS"),
  port = 3306
)

# simple UI with user info
ui <- navbarPage(
  title = "Full Send",
  
  tabPanel("Routes",
           # shinyWidgets::switchInput(
           #   inputId = "",
           #   onLabel = "Sent!",
           #   offLabel = "Did Not Send",
           #   onStatus = 'success',
           #   offStatus = 'warning'
           # )
           uiOutput
  ),
  
  tabPanel("User Info",
           verbatimTextOutput("user_info")),
  
  tabPanel("Credential Info",
           verbatimTextOutput("credential_info")),
  
  logoutButton()
  
)

server <- function(input, output, session) {
  
  current_routes <- reactive({
      dbGetQuery(pool, "SELECT * FROM routes")
  })
  
  output$routeInputButtons <- renderUI({
    
    routeList <- lapply(current_routes(), function(i) {
      name <- paste("route", i, sep="")
      shinyWidgets::switchInput(
        inputId = ,
        onLabel = "Sent!",
        offLabel = "Did Not Send",
        onStatus = 'success',
        offStatus = 'warning'
      )
    })
    do.call(tagList, unlist(routeList, recursive = FALSE))
  })
  
  # print user info
  output$user_info <- renderPrint({
    session$userData$auth0_info
  })
  
  output$credential_info <- renderPrint({
    session$userData$auth0_credentials
  })
  
}

# note that here we're using a different version of shinyApp!
shinyAppAuth0(ui, server)