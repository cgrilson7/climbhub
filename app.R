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
ui <- fluidPage(theme = "style.css",
  
  useShinyjs(),

                
  titlePanel("ClimbHub", windowTitle="Track your sends"),
  
  tabsetPanel(
    
    tabPanel("Routes",
             uiOutput("gym_selectize"),
             div(align = "center",
                 plotOutput("gym_blueprint",
                            height = 350,
                            click = "plot_click"
                            )
             ),
             br(),
             # verbatimTextOutput("click_info"),
             
             div(style = 'overflow-x:scroll;',
                 uiOutput(outputId="route_switch_inputs")
                 ),

             br(),
             # verbatimTextOutput("routes_for_submission"),
             br(),
             # DTOutput("gym_routes_datatable")
             absolutePanel(bottom = 5, left = 0, right = 0, fixed = TRUE,
                           div(align = "center",
                               # div(style="display:inline-block",
                               #   actionButton('goto_gym_blueprint',
                               #                label = "Return to Map",
                               #                icon = icon("map", class = "far"),
                               #                width = '300px')
                               #  ),
                               div(style="display:inline-block",
                                   actionButton('submit_route_switch_inputs',
                                                label = "Submit Climbs",
                                                icon = icon("cloud-upload-alt"),
                                                width = '300px')
                               )
                           )
             )
    ),
    
    # tabPanel("User Info",
    #          verbatimTextOutput("user_info")
    #          ),
    
    tabPanel("Log Out",
             br(),
             logoutButton(label = 'Log Out', width = '400px', height = '200px'),
             br()
    )
    
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
  
  output$gym_selectize <- renderUI({
    gyms <- dbGetQuery(pool, 'select gym_name, gym_id from gyms where blueprint is not null')
    selectizeInput(
      'selected_gym',
      label = '',
      choices = tibble::deframe(gyms)
    )
  })
  
  # Generate gym blueprint
  output$gym_blueprint <- renderPlot({
    
    req(input$selected_gym)
    
    sql <- sqlInterpolate(pool, 'SELECT ST_AsWKT(blueprint) as WKT FROM gyms WHERE GYM_ID = ?gym_id',
                          gym_id = input$selected_gym)
    
    gym_polygon_df <-
      dbGetQuery(pool, sql) %>%
      `[`(1) %>% readWKT() %>% 
      `@`(polygons) %>% `[[`(1) %>% `@`(Polygons) %>% `[[`(1) %>% `@`(coords) %>% as_tibble()
    
    ggplot(gym_polygon_df, aes(x=x, y=y)) + 
      geom_polygon(fill="#28c9c4") +
      ylim(min(gym_polygon_df$y) - 10, 100) +
      theme_void() + 
      theme(plot.margin=unit(c(0,0,0,0), "mm"),
            panel.background=element_rect(fill="#333333")) 
    
  })
  
  output$click_info <- renderPrint({
    cat("input$plot_click:\n")
    str(input$plot_click)
  })
  
  gym_routes <- reactive({
    req(input$selected_gym)

    sql <- sqlInterpolate(pool, 'SELECT * FROM routes WHERE gym_id = ?gym_id AND date_replaced IS NULL',
                          gym_id = input$selected_gym)
    
    dbGetQuery(pool, sql) %>%
      arrange(route_x)
    
  })
  
  output$gym_routes_datatable <- renderDT(gym_routes())
  
  output$route_switch_inputs <- renderUI({
    req(input$selected_gym)
    
    routes <- gym_routes() %>% select(route_id, color, grade_v)
    
    f <- function(route_id,color,grade_v){
      div(class="same-row", align = "center",
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
          choices = c("Sent"),
          direction = 'vertical',
          status = 'primary',
          checkIcon = list(
            yes = icon("ok", 
                       lib = "glyphicon"),
            no = icon("remove",
                      lib = "glyphicon"))
        )
      )
    }
    
    purrr::pmap(routes, f)
    
  })
  
  observeEvent(input$plot_click, {
    # get closest route to click
    route_switch_id <- gym_routes() %>% 
      mutate(d = sqrt((input$plot_click$x - route_x)^2 + (input$plot_click$y - route_y)^2)) %>% 
      top_n(-1, d) %>% 
      pull(route_id) %>% 
      paste0("route_", .)
      
    js_text <- paste0("document.getElementById('", route_switch_id, "').scrollIntoView({behavior: 'smooth', inline: 'center'})")

    print(js_text)
    
    shinyjs::runjs(js_text)
    
  })
  
  observeEvent(input$goto_gym_blueprint, {
    
    shinyjs::runjs("document.getElementById('gym_blueprint').scrollIntoView({behavior: 'smooth'})")
    
  })
  
  observeEvent(input$submit_route_switch_inputs, {
    
    req(input$selected_gym)
    
    route_switch_ids <- gym_routes() %>% 
      pull(route_id) %>% 
      paste0("route_", .)
    
    sends <- route_switch_ids %>%
      map_df(~data.frame(route = .x, value = ifelse(is.null(input[[.x]]), NA, input[[.x]]), stringsAsFactors = FALSE)) %>% 
      filter(value == "Sent") %>% 
      mutate(route_id = as.integer(substr(route, 7, nchar(route))),
             climber_auth0 = session$userData$auth0_info$sub) %>% 
      select(route_id, climber_auth0)
    
    write <- function(route_id, climber_auth0){
      sql <- paste0("INSERT INTO sends (route_id, climber_auth0) VALUES (", route_id, ", '", climber_auth0, "')")
      dbExecute(pool, sql)
    }
    
    purrr::pmap(sends, write)
    
    lapply(route_switch_ids, function(x){updateCheckboxGroupButtons(session, x, selected = character(0))})
     
  })
  
  # output$routes_for_submission <- renderPrint({
    
    req(input$selected_gym)
    
    route_switch_ids <- gym_routes() %>% 
      pull(route_id) %>% 
      paste0("route_", .)
    
    route_switch_ids %>%
      map_df(~data.frame(route = .x, value = ifelse(is.null(input[[.x]]), NA, input[[.x]]), stringsAsFactors = FALSE))
    
  })
  
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
  
  onStop(function() pool::poolClose(pool))
  
}

shinyAppAuth0(ui, server)
# shiny::shinyApp(ui, server)