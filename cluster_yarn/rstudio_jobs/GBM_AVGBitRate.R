
#
# DeepLearning
library(dplyr)
library(sparklyr)
library(h2o)
options(rsparkling.sparklingwater.version = "2.1.27",rsparkling.sparklingwater.location = "/home/analyticsdb/spark/sparklingwater/sparkling-water-2.1.27/assembly/build/libs/sparkling-water-assembly_2.11-2.1.27-all.jar")
library(rsparkling)

ip <- as.data.frame(installed.packages()[,c(1,3:4)])
ip <- ip[is.na(ip$Priority),1:2,drop=FALSE]
print(ip, row.names=FALSE)
rownames(ip) <- NULL

# h2o to be restarted in every session
h2o.shutdown()
# h2o port is redirected from 54321 to 54323 for spark mode=local
#
h2o.init(ip = "localhost", port = 54321, startH2O = TRUE,
         forceDL = FALSE, enable_assertions = TRUE, license = NULL,
         nthreads = 2, max_mem_size = NULL, min_mem_size = NULL,
         ice_root = tempdir(), strict_version_check = TRUE,
         proxy = NA_character_, https = FALSE, insecure = FALSE,
         username = NA_character_ , password = NA_character_ ,
         cookies = NA_character_, context_path = NA_character_ )

h2o.clusterInfo()
spark_home_dir()

# restart r session
#sessionInfo()
#options(rsparkling.sparklingwater.version = "1.6.2")
#spark_install(version = "1.6.2")
#spark_home_set(path="/home/analyticsdb/spark/spark-1.6.2-bin-hadoop2.6")
#sc <- spark_connect(master = "local", version = "1.6.2", config = list(sparklyr.log.console = TRUE))

# FIX FROM GITGUB : https://github.com/rstudio/sparklyr/issues/801
# FIX PROXY SERVER for SPARK2
#sessionInfo()
#devtools::install_github("rstudio/sparklyr")

# restart r session
sessionInfo()
# Match rsparkling with spark2.1 and H2O verison from https://github.com/h2oai/rsparkling/blob/master/README.md 
# Download from : http://h2o-release.s3.amazonaws.com/sparkling-water/rel-2.1/27/index.html 
# Wait for 15 minutes, might require even more.
# Load parameters from condaR zip

#spark_home_set(path="/home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7")

config <- spark_config()
spark_home <- "/home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7"
spark_version <- "2.1.0"
config$spark.executor.cores=1
config$spark.executor.memory="1g"
config$`sparklyr.shell.driver-memory` <- "1g"
config$`sparklyr.shell.executor-memory` <- "1g"
config$spark.executor.instances=2
config$spark.driver.memory="2g"
config$spark.driver.cores   <- 2
config$spark.dynamicAllocation.enabled='false'
config[["spark.r.command"]] <- "/home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7/r_env.zip/r_env/bin/Rscript"
config[["spark.yarn.dist.archives"]] <- "/home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7/r_env.zip"
config$sparklyr.apply.env.R_HOME <- "./home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7/r_env.zip/r_env/lib/R"
config$sparklyr.apply.env.RHOME <- "./home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7/r_env.zip/r_env"
config$sparklyr.apply.env.R_SHARE_DIR <- "./home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7/r_env.zip/r_env/lib/R/share"
config$sparklyr.apply.env.R_INCLUDE_DIR <- "./home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7/r_env.zip/r_env/lib/R/include"
config$sparklyr.apply.env.LD_LIBRARY_PATH <- "/opt/cloudera/parcels/Anaconda/lib"
config$sparklyr.apply.env.PYTHONPATH <- "./home/analyticsdb/spark/spark-2.1.0-bin-hadoop2.7/r_env.zip/r_env/lib/python2.7/site/packages"
# Force Driver and host from gateway
config$spark.jars <- "file:/data/analyticsdb/spark/sparklingwater/sparkling-water-2.1.27/assembly/build/libs/sparkling-water-assembly_2.11-2.1.27-all.jar,file:/usr/lib64/R/library/sparklyr/java/sparklyr-2.1-2.11.jar"
config$spark.driver.host <- "10.12.61.19"
# ISSUE https://github.com/h2oai/sparkling-water/issues/32
config$spark.ext.h2o.topology.change.listener.enabled <- TRUE
config$spark.ext.h2o.ip <- "localhost"
config$spark.ext.h2o.nthreads <- 2
config$spark.ext.h2o.port <- 54321
# ISSUE https://github.com/h2oai/sparkling-water/issues/466
config$spark.executor.heartbeatInterval <- 6000
config$sparklyr.gateway.start.timeout <- 6000
### Enable visualization of detailed logs
config$sparklyr.log.console <- TRUE
#config$sparklyr.log.console <- FALSE

system.time(sc <- spark_connect(master = "yarn-client", app_name = "jpac-sparklyr", version = spark_version, config = config, spark_home=spark_home))
#system.time(sc <- spark_connect(master = "local", app_name = "jpac-sparklyr", version = spark_version , config = config, spark_home=spark_home))

spark_context(sc)
spark_context_config(sc)

## ISSUE : https://github.com/h2oai/sparkling-water/issues/32
h2o_context(sc)

conviva_file <- read.csv("/home/analyticsdb/projects/r-studio/AVG_Bitrate/conviva11.csv")
head(conviva_file)

conviva_csv_df <- spark_read_csv(sc,"conviva","hdfs://bda-ns//user/analyticsdb/conviva11.csv")
head(conviva_csv_df)

actual_conviva_df <- conviva_csv_df %>%
  select(average_bitrate_kbps) %>%
  collect() %>%
  `[[`("average_bitrate_kbps")
head(actual_conviva_df)

conviva_tbl <- copy_to(sc, conviva_csv_df, "conviva_tbl", overwrite = TRUE)
head(conviva_tbl)

#Convert to an H2O Frame:
conviva_hf <- as.h2o(conviva_tbl)

#
# Test 1  :Model: Deep Neural Network
#
splits <- h2o.splitFrame(conviva_hf, seed = 1099)

y <- "average_bitrate_kbps"
#remove response and ID cols
x <- setdiff(names(conviva_hf), c("viewerId", y))
# Print Header of the Variables
x

# Train a Deep Neural Network
dl_fit <- h2o.deeplearning(x = x, y = y,
                           training_frame = splits[[1]],
                           epochs = 999,
                           activation = "Rectifier",
                           hidden = c(10, 5, 10),
                           input_dropout_ratio = 0.78)

h2o.performance(dl_fit, newdata = splits[[2]])

# Apply prediction from the achieved Model
pred_model_dl_fit <- h2o.predict(dl_fit, newdata = conviva_hf)
head(pred_model_dl_fit)
head(conviva_hf)

predicted_model_dl_fit <- as.data.frame(pred_model_dl_fit)

actual_conviva_df <- conviva_csv_df %>%
  select(average_bitrate_kbps) %>%
  collect() %>%
  `[[`("average_bitrate_kbps")
head(actual_conviva_df)

# produce a data.frame housing our predicted + actual values of AVGBITRATE  actual_conviva_df
data <- data.frame(
  predicted = predicted_model_dl_fit,
  actual    = actual_conviva_df)

# a bug in data.frame does not set colnames properly; reset here 
names(data) <- c("predicted", "actual")

# plot predicted vs. actual values
ggplot(data, aes(x = actual, y = predicted)) +
  geom_abline(lty = "dashed", col = "red") +
  geom_point() +
  theme(plot.title = element_text(hjust = 0.3)) +
  coord_fixed(ratio = 3.0) +
  labs(
    x = "Actual AVG BitRate",
    y = "Predicted AVG BitRate",
    title = "DL-FIT Predicted vs. Actual AVG BitRate"
  )

#
# Test 2  :Model: GBM (Gradient Boost Machine)
#
# Cartesian Grid Search
# New Split
splits <- h2o.splitFrame(conviva_hf, seed = 999999)

y <- "average_bitrate_kbps"
#remove response and ID cols
x <- setdiff(names(conviva_hf), c("viewerId", y))
# Print Header of the Variables
x

# GBM hyperparamters
gbm_params1 <- list(learn_rate = c(0.5, 1.0),
                    max_depth = c(3, 5, 9),
                    sample_rate = c(0.8, 1.0),
                    col_sample_rate = c(0.1, 0.5, 1.0))

# Takes 2 minutes to obtain the grid of models
# Models available later in http://ixpbdaopta01.prod.ix.perform.local:54321/flow/index.html 
#
# Train and validate a grid of GBMs
gbm_grid1 <- h2o.grid("gbm", x = x, y = y,
                      grid_id = "gbm_grid1",
                      training_frame = splits[[1]],
                      validation_frame = splits[[1]],
                      ntrees = 1000,
                      seed = 999999,
                      hyper_params = gbm_params1)

# Get the grid results, sorted by validation MSE
gbm_gridperf1 <- h2o.getGrid(grid_id = "gbm_grid1", 
                             sort_by = "mse", 
                             decreasing = FALSE)

# Print grid results
print(gbm_gridperf1)

# best model in grid according to mse
gbm_gridperf1@model_ids[[1]]

gbm_model_gridperf1 <- h2o.getModel(gbm_gridperf1@model_ids[[1]])

#Apply prediction from the best MSE qualifyed Model
pred_model_gridperf1 <- h2o.predict(gbm_model_gridperf1, newdata = conviva_hf)

head(pred_model_gridperf1)

predicted_model_gridperf1 <- as.data.frame(pred_model_gridperf1)

actual_conviva_df <- conviva_csv_df %>%
  select(average_bitrate_kbps) %>%
  collect() %>%
  `[[`("average_bitrate_kbps")
head(actual_conviva_df)

# produce a data.frame housing our predicted + actual 'VOL' values of prostate_df
data <- data.frame(
  predicted = predicted_model_gridperf1,
  actual    = actual_conviva_df)

# a bug in data.frame does not set colnames properly; reset here 
names(data) <- c("predicted", "actual")

# plot predicted vs. actual values
ggplot(data, aes(x = actual, y = predicted)) +
  geom_abline(lty = "dashed", col = "red") +
  geom_point() +
  theme(plot.title = element_text(hjust = 0.8)) +
  coord_fixed(ratio = 3.5) +
  labs(
    x = "Actual AVG BitRate",
    y = "Predicted AVG BitRate",
    title = "CGRID-GBM-MSE_1 Predicted vs. Actual AVG BitRate" )

# local Dir in node home/analyticsdb for external storage of model
tmpdir_model <- "h2omodels-v1-avg-bitrate"
dir.create(tmpdir_model)
# print the centroid statistics
h2o.centroid_stats(gbm_model_gridperf1)
# Save generic Model
h2o.saveModel(gbm_model_gridperf1, path = tmpdir_model)
# Export Model as a POJO with H2O
h2o.download_pojo(gbm_model_gridperf1, path = tmpdir_model)
# Export Model as a MOJO with H2O
h2o.download_mojo(gbm_model_gridperf1, path = tmpdir_model)
y
x
spark_disconnect(sc)
h2o.shutdown()
quit()

############################  Do NOT RUN FROM HERE ################

# Random Grid Search
# GBM hyperparamters
