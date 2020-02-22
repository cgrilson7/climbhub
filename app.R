library(shiny)
library(auth0)
library(pool)
library(DBI)
library(shinyWidgets)

#
pool <- dbPool(
  drv = RMariaDB::MariaDB(),
  dbname = "appdata",
  host = Sys.getenv("FULLSEND_HOST"),
  username = Sys.getenv("FULLSEND_USER"),
  password = Sys.getenv("FULLSEND_PASS"),
  port = 3306
)

DBI::dbGetQuery(pool, "select ST_AsText(blueprint) from gyms where gym_id=1")

# simple UI with user info
ui <- navbarPage(
  title = "Full Send",
  
  tabPanel("Routes",
           imageOutput("gym_blueprint", height = 350,
                       click = "image_click"
                       ),
           shinyWidgets::switchInput(
             inputId = "",
             onLabel = "Sent!",
             offLabel = "Did Not Send",
             onStatus = 'success',
             offStatus = 'warning'
           )
           # uiOutput()
  ),
  
  tabPanel("User Info",
           verbatimTextOutput("user_info")),
  
  tabPanel("Credential Info",
           verbatimTextOutput("credential_info")),
  
  logoutButton()
  
)

server <- function(input, output, session) {
  
  # Generate an image with black lines every 10 pixels
  output$gym_blueprint <- renderImage({
    # Get width and height of image output
    width  <- session$clientData$output_gym_blueprint_width
    height <- session$clientData$output_gym_blueprint_height
    npixels <- width * height
    
    # Fill the pixels for R, G, B
    m <- matrix(1, nrow = height, ncol = width)
    # Add gray vertical and horizontal lines every 10 pixels
    m[seq_len(ceiling(height/10)) * 10 - 9, ] <- 0.75
    m[, seq_len(ceiling(width/10)) * 10 - 9]  <- 0.75
    
    # Convert the vector to an array with 3 planes
    img <- array(c(m, m, m), dim = c(height, width, 3))
    
    # Write it to a temporary file
    outfile <- tempfile(fileext = ".png")
    writePNG(img, target = outfile)
    
    # Return a list containing information about the image
    list(
      src = outfile,
      contentType = "image/png",
      width = width,
      height = height,
      alt = "This is alternate text"
    )
  })
  
  output$click_info <- renderPrint({
    cat("input$image_click:\n")
    str(input$image_click)
  })
  
  current_routes <- reactive(input$image_click, {
    dplyr::tbl(pool, routes) %>% 
      mutate(d = sqrt((input$image_click$x - route_x)^2 + (input$image_click$y - route_y)^2)) %>% 
      arrange(d)
  })
  
  # output$route_switch_inputs <- renderUI({
  #   route_list <- lapply(current_routes(), function(i) {
  #     name <- paste("route", i, sep="")
  #     shinyWidgets::switchInput(
  #       inputId = ,
  #       onLabel = "Sent!",
  #       offLabel = "Did Not Send",
  #       onStatus = 'success',
  #       offStatus = 'warning'
  #     )
  #   })
  #   do.call(tagList, unlist(routeList, recursive = FALSE))
  # })
  
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