library(shiny)
library(auth0)
library(pool)
library(DBI)
library(dplyr)
library(rgeos)
library(sp)
library(ggplot2)
library(DT)
library(shinyjs)
library(tidyr)
library(shinyWidgets)
library(purrr)

# Set up pool
pool <- dbPool(
  drv = RMariaDB::MariaDB(),
  dbname = "appdata",
  host = Sys.getenv("FULLSEND_HOST"),
  username = Sys.getenv("FULLSEND_USER"),
  password = Sys.getenv("FULLSEND_PASS"),
  port = 3306
)


# UI section --------------------------------------------------------------

ui <- fluidPage(theme = "style.css",
  
  # allows app to run custom js     
  useShinyjs(),
  
  # allows app to run sweetAlerts
  useSweetAlert(),

  # Title and tab/window header
  titlePanel("ClimbHub", windowTitle="Track your sends"),
  
  # Tab-based layout
  tabsetPanel(
    
    # Main tab flow:
    # - User selects their gym
    # - Plot of gym blueprint rendered
    # - User taps/clicks the plot near the routes they have climbed
    # - Horizontal bar of routes scrolls to the routes nearest to the user's click
    # - User checks off routes
    # - User repeats the above 3 steps until they have checked the routes they wish to submit
    # - User submits routes, which are written to the MySQL database and given a timestamp (time of the send) 
    # - Route checkboxes are reset
    
    tabPanel("Routes",
             
             # User selects their gym
             div(align = "center",
                 uiOutput("gym_selectize")
            ),
             
             # Plot of gym blueprint rendered
             div(align = "center",
                 plotOutput("gym_blueprint",
                            height = 350,
                            click = "plot_click")
             ),
             
             br(),
             
             # Horizontal bar of routes scrolls to the routes nearest to the user's click
             div(style = 'overflow-x:scroll; -webkit-overflow-scrolling: touch;',
                 uiOutput(outputId="route_check_inputs")
             ),

             br(), br(),

             # User submits routes, which are written to the MySQL database and given a timestamp (time of the send) 
             div(align="center", 
                 actionButton('submit_route_check_inputs',
                          label = "Submit Climbs",
                          icon = icon("cloud-upload-alt"),
                          width = '300px')
             )
    ),
    
    # Logout tab & button
    tabPanel("Log Out",
             br(),
             logoutButton(label = 'Log Out', width = '400px', height = '200px'),
             br()
    )
    
    # tabPanel("User Info",
    #          verbatimTextOutput("user_info")
    #          ),
    
    
    # tabPanel("Client Info",
    #          verbatimTextOutput("client_info")
    #          ),
    

    # 
    # tabPanel("Credential Info",
    #          verbatimTextOutput("credential_info")
    #          ),
  )
)

server <- function(input, output, session) {
  
  # Render selectizeInput with all gyms in the database that have a blueprint
  output$gym_selectize <- renderUI({
    gyms <- dbGetQuery(pool, 'select gym_name, gym_id from gyms where blueprint is not null')
    selectizeInput(
      'selected_gym',
      label = '',
      choices = tibble::deframe(gyms)
    )
  })
  
  # gym_polygon()
  # req(s): input$selected_gym
  # Returns a tibble of gym polygon coordinates to be used for plotting
  gym_polygon <- reactive({
    
    req(input$selected_gym)
    
    sql <- sqlInterpolate(pool, 'SELECT ST_AsWKT(blueprint) as WKT FROM gyms WHERE GYM_ID = ?gym_id',
                          gym_id = input$selected_gym)
    
    dbGetQuery(pool, sql) %>%
      `[`(1) %>% readWKT() %>% 
      `@`(polygons) %>% `[[`(1) %>% `@`(Polygons) %>% `[[`(1) %>% `@`(coords) %>%
      as_tibble()

  })
  
  # Plot gym polygon
  output$gym_blueprint <- renderPlot({
    
    df <- gym_polygon()
    
    df %>% 
      ggplot(aes(x=x, y=y)) + 
        geom_polygon(fill="#28c9c4", color="#ffffff", size = 2) +
        ylim(min(df$y) - 10, 100) +
        theme_void() + 
        theme(plot.margin=unit(c(0,0,0,0), "mm"),
              panel.background=element_rect(fill="#333333")) 
    
  })

  # gym_routes()
  # req(s): input$selected_gym
  # Returns all of the selected gym's current routes, ordered from left to right (route_x ascending)
  gym_routes <- reactive({
    req(input$selected_gym)

    sql <- sqlInterpolate(pool, 'SELECT * FROM routes WHERE gym_id = ?gym_id AND date_replaced IS NULL',
                          gym_id = input$selected_gym)
    
    dbGetQuery(pool, sql) %>%
      arrange(route_x)
  })
  
  # gym_routes_click_distance()
  # req(s): input$plot_click, gym_routes()
  # Adds a column to gym_routes() containing the distance from each route to the user's click
  gym_routes_click_distance <- eventReactive(input$plot_click, {
    gym_routes() %>% 
      mutate(d = sqrt((input$plot_click$x - route_x)^2 + (input$plot_click$y - route_y)^2))
  })
  
  # Generate checkboxes for each route in the gym
  # req(s): input$selected_gym
  output$route_check_inputs <- renderUI({
    
    req(input$selected_gym)
    
    # Get only the columns needed to generate the checkbox
    routes <- gym_routes() %>% select(route_id, color, grade_v)
    
    # This function will be applied to every row in ^
    generate_single_checkbox <- function(route_id,color,grade_v){
      # Generate a custom div, .routes_row, with properties defined in style.css
      div(class="routes-row", align = "center",
          # Inside of which is a checkbox:
            shinyWidgets::checkboxGroupButtons(
              inputId = paste0("route_",route_id),
              label = div(align = "center",
                style = paste(
                  "text-align:center",
                  "font-size:30px",
                  "font-weight:bold",
                  paste0("color:", color, ";"), sep="; "
                ),
                paste0("V",grade_v)
              ),
              # Currently, only one choice (binary)
              choices = c("Sent"),
              # If more choices added, will stack vertically
              direction = 'vertical',
              # status controls the color of the buttons
              status = 'primary',
              # icons for sent / not sent
              checkIcon = list(
                yes = icon("ok", 
                           lib = "glyphicon"),
                no = icon("remove",
                          lib = "glyphicon"))
            )
      )
    }
    
    # Use pmap to apply the function to all routes (returns a list of divs)
    purrr::pmap(routes, generate_single_checkbox)
    
  })
  
  # Scroll to checkboxes nearest to user's click
  # req(s): gym_routes_click_distance()
  observeEvent(input$plot_click, {
    # get closest route to click
    route_check_id <- gym_routes_click_distance() %>% 
      top_n(-1, d) %>% 
      pull(route_id) %>% 
      paste0("route_", .)
      
    # prepare JS call to .scrollIntoView() 
    js_text <- paste0("document.getElementById('", route_check_id, "').scrollIntoView({behavior: 'smooth', inline: 'center'})")

    # run JS
    shinyjs::runjs(js_text)
    
  })
  
  # Write checked routes to 
  observeEvent(input$submit_route_check_inputs, {
    
    req(input$selected_gym)
    
    # Get atomic vector of route_ids with "route_" prepended.
    route_check_ids <- gym_routes() %>% 
      pull(route_id) %>% 
      paste0("route_", .)
    
    # Map route_ids and the values of their checkboxes to a dataframe, filter for sends, and add the user's auth0 sub value
    # as a column.
    sends <- route_check_ids %>%
      map_df(~data.frame(route = .x, value = ifelse(is.null(input[[.x]]), NA, input[[.x]]), stringsAsFactors = FALSE)) %>% 
      filter(value == "Sent") %>% 
      mutate(route_id = as.integer(substr(route, 7, nchar(route))),
             climber_auth0 = session$userData$auth0_info$sub) %>% 
      select(route_id, climber_auth0)
    
    # If the user has checked more than 0 routes, write these to the database.
    if(nrow(sends) > 0){
      
      write <- function(route_id, climber_auth0){
        sql <- paste0("INSERT INTO sends (route_id, climber_auth0) VALUES (", route_id, ", '", climber_auth0, "')")
        dbExecute(pool, sql)
      }
      
      # As with the creation of checkboxes, apply the write function to the dataframe of sends using purrr::pmap
      purrr::pmap(sends, write)
      
      # Notify user their sends have been written to the database
      # TODO: implement an actual check here
      sendSweetAlert(
        session = session,
        title = "Success!",
        text = "Your sends have been uploaded to the ClimbHub Cloud",
        type = "success"
      )
      
      # Reset checkboxes
      lapply(route_check_ids, function(x){updateCheckboxGroupButtons(session, x, selected = character(0))})
      
    } else {
      # the user has not checked any routes, or there was an issue when creating the sends data.frame
      sendSweetAlert(session,
                     title = "Error",
                     text = "Try again. Make sure your sends have been checked off!", type = "warning"
                     )
    }
     
  })
  

# Debugging / deprecated functions ----------------------------------------

  # ---Deprecated---
  # Returns viewport to gym_blueprint
  observeEvent(input$goto_gym_blueprint, {
    
    shinyjs::runjs("document.getElementById('gym_blueprint').scrollIntoView({behavior: 'smooth'})")
    
  })
  
  
  output$print_route_check_inputs <- renderPrint({
    
    req(input$selected_gym)
    
    route_check_ids <- gym_routes() %>% 
      pull(route_id) %>% 
      paste0("route_", .)
    
    route_check_ids %>%
      map_df(~data.frame(route = .x, value = ifelse(is.null(input[[.x]]), NA, input[[.x]]), stringsAsFactors = FALSE))
    
  })
  

  
  # print info on all of the gym's routes
  output$gym_routes_datatable <- renderDT(gym_routes())
  
  # print client info
  output$client_info <- renderPrint({
    session$clientData
  })
  
  # print user info
  output$user_info <- renderPrint({
    session$userData$auth0_info
  })
  
  output$credential_info <- renderPrint({
    session$userData$auth0_credentials
  })

}
  
# onStop: close pool -----------------------------------------------------------------
onStop(function() pool::poolClose(pool))
  

# Start app ---------------------------------------------------------------

shinyAppAuth0(ui, server)
# shiny::shinyApp(ui, server)