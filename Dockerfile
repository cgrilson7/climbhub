FROM rocker/shiny-verse:latest

# install system libraries
RUN apt-get update && apt-get install -y \
    sudo \
    pandoc \
    pandoc-citeproc \
    libcurl4-gnutls-dev \
    libcairo2-dev \
    libxt-dev \
    libssl-dev \
    libssh2-1-dev \
    gdal-bin \
    libgeos-dev \ 
    libproj-dev \
    libgdal-dev \
    libudunits2-dev
    
# install renv for R package management
ENV RENV_VERSION 0.9.3
RUN R -e "install.packages('remotes', repos = c(CRAN = 'https://cloud.r-project.org'))"
RUN R -e "remotes::install_github('rstudio/renv@${RENV_VERSION}')"

# copy over renv.lock file, and run renv::restore() there to install all packages needed by app
COPY renv.lock renv.lock
RUN R -e "renv::restore()"

# Transfer app and associated files:
# copy app and .Renviron (contains secrets) into the container
COPY .Renviron /srv/shiny-server/
COPY _auth0.yml /srv/shiny-server/
COPY app.R /srv/shiny-server/
# copy 'in' folder
# COPY in /srv/shiny-server/in
# copy 'www' folder
COPY www /srv/shiny-server/www

# expose port 3838
EXPOSE 3838

# give the 'shiny' user ownership of all files under /srv/shiny-server
# RUN sudo chown -R shiny:shiny /srv/shiny-server

# Edit the default rocker/shiny shiny-server.conf file, copying in the one in the repo:
COPY shiny-server.conf /etc/shiny-server/shiny-server.conf

# boot up the shiny-server
CMD ["/usr/bin/shiny-server.sh"]