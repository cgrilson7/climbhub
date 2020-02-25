library(shiny)
library(auth0)
library(pool)
library(DBI)
library(dplyr)
library(rgeos)
library(sp)
library(ggplot2)
library(DT)

# Set up pool
pool <- dbPool(
  drv = RMariaDB::MariaDB(),
  dbname = "appdata",
  host = Sys.getenv("FULLSEND_HOST"),
  username = Sys.getenv("FULLSEND_USER"),
  password = Sys.getenv("FULLSEND_PASS"),
  port = 3306
)

# Simple UI with user info
ui <- navbarPage(

  title = "Full Send",
  
  tabPanel("Routes",
           uiOutput("gym_selectize"),
           plotOutput("gym_blueprint", height = 350,
                       click = "plot_click"
                       ),
           verbatimTextOutput("click_info"),
           uiOutput("route_switch_inputs"),
           DTOutput("current_routes_dt")
  ),
  
  # tabPanel("Client Info",
  #          verbatimTextOutput("client_info")
  #          ),
  
  tabPanel("User Info",
           verbatimTextOutput("user_info")
           ),
  
  tabPanel("Credential Info",
           verbatimTextOutput("credential_info")
           ),
  
  logoutButton()
  
)

server <- function(input, output, session) {
  
  output$gym_selectize <- renderUI({
    selectizeInput('selected_gym', label = 'Choose your gym', choices = c('Central Rock Gym - North Station' = 1))
  })
  
  # Generate gym blueprint
  output$gym_blueprint <- renderPlot({
    
    req(input$selected_gym)
    gym_id <- input$selected_gym
    
    gym_polygon_df <-
      dbGetQuery(pool, paste0('select ST_AsWKT(blueprint) as wkt from gyms where gym_id=', gym_id)) %>%
      `[`(1) %>% readWKT() %>% 
      `@`(polygons) %>% `[[`(1) %>% `@`(Polygons) %>% `[[`(1) %>% `@`(coords) %>% as_tibble()
    
    ggplot(gym_polygon_df, aes(x=x, y=y)) + 
      geom_polygon(fill="navy") +
      ylim(min(gym_polygon_df$y) - 10, 100) +
      # theme_minimal() +
      # theme(axis.title = element_blank(),
      #       panel.grid = element_blank())
      theme_void() + 
      theme(plot.margin=unit(c(0,0,0,0), "mm"))
    
  })
  
  output$click_info <- renderPrint({
    cat("input$plot_click:\n")
    str(input$plot_click)
  })
  
  current_routes <- reactive({
    req(input$selected_gym)
    req(input$plot_click)
    selected_gym_id <- input$selected_gym
    
    dplyr::tbl(pool, 'routes') %>% 
      filter(gym_id == selected_gym_id,
             is.null(date_replaced)) %>%
      collect() %>% 
      mutate(d = sqrt((input$plot_click$x - route_x)^2 + (input$plot_click$y - route_y)^2)) %>% 
      top_n(-5, d) %>% 
      arrange(route_x) %>% 
      select(route_id, color, grade_v)
  })
  
  output$current_routes_dt <- renderDT(current_routes())
  
  output$route_switch_inputs <- renderUI({
    req(input$plot_click)
    routes <- current_routes()
    f <- function(route_id,color,grade_v){shinyWidgets::switchInput(
      inputId = paste0("route_",route_id),
      label = div(style = paste0("color:", color), paste0("V",grade_v)),
      onLabel = "Sent!",
      offLabel = "Did Not Send",
      onStatus = 'success',
      offStatus = 'warning'
    )}
    purrr::pmap(routes, f)
    })
  
  # print client info
  # output$client_info <- renderPrint({
  #   session$clientData
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
# shiny::shinyApp(ui, server)