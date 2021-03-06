rm(list = ls())

# set working directory
setwd("Downloads/Data Science Problem sets/ChurnRate")

# importing test and train data into dataframes by and removing whitespaces
train_dataset = read.csv("Train_Data.csv", header = T, strip.white= T )
test_dataset= read.csv("Test_Data.csv", header = T, strip.white= T )
FinalResult_R <- cbind(NA, NA)
FinalResult_R <- cbind(test_dataset)

# renaming column names
names(train_dataset) = gsub("\\.", "_", names(train_dataset))
names(test_dataset) = gsub("\\.", "_", names(test_dataset))


# getting the descriptive statistics of the dataset
summary(train_dataset)

# label encoding target class
levels(train_dataset$Churn) = c(0:(length(levels(train_dataset$Churn))-1))
levels(test_dataset$Churn) = c(0:(length(levels(test_dataset$Churn))-1))

# correlation matrix of all numeric predictors and target variable                        
dataset_corr = data.frame(lapply(train_dataset, function(x) {
  if(is.integer(x)) as.numeric(x) else  x}))
dataset_corr$Churn = as.numeric(as.character(dataset_corr$Churn))
correlation_matrix = cor(dataset_corr[sapply(dataset_corr, is.numeric)], method = 'pearson')


# histograms to observe distribution for all numeric predictors
df_columns = data.frame("colType"=sapply(dataset_corr, function (x) class(x)))
df_columns$colName = rownames(df_columns)
df_columns = df_columns[-c(21),]
rownames(df_columns) = NULL


nCol = nrow(df_columns)
for(i in 1:nCol){
  if(df_columns[i,1]=="numeric"){
        hist(train_dataset[,df_columns[i,2]],
         breaks=50,
         main="HISTOGRAM",
         xlab=paste(df_columns[i,2],sep=""),
         ylab="Count",
         col="green",
         border="red" )
  }
}


# plotting boxplots for all numeric variables for each target class
df_columns = df_columns[-c(3),]
nCol = nrow(df_columns)
for(i in 1:nCol){
  if(df_columns[i,1]=="numeric"){
    boxplot(train_dataset[,df_columns[i,2]] ~ Churn,
            data = train_dataset,
            xlab='Churn',
            ylab=paste(df_columns[i,2],sep=""))
  }            
}


# plotting bar charts for categorical variables with respect to their 
# distribution in each target class
cat_Features = c('international_plan','voice_mail_plan','state','area_code')
for(feature in cat_Features){
crosstab_churn = table(train_dataset$Churn, train_dataset[[feature]])
barplot(crosstab_churn, main="Distribution per Target Class",
        xlab=feature, col=c("red","green"),
        ylab ='Churn', 
        legend = rownames(crosstab_churn))
}


# adding a column 'Source' to distinguish between test and train data
train_dataset$Source = 'train'
test_dataset$Source = 'test'

# combining test and train dataset to preprocess both the dataset at once
dataset = rbind(train_dataset, test_dataset)


# finding the count of missing values 
missing_values = data.frame(c(sapply(dataset, function(x)  sum(is.na(x)))))
colnames(missing_values) = 'Count'


# label encoding factor variables
map_value = c('voice_mail_plan', 'international_plan')
for (feature in map_value)
{
  levels(dataset[[feature]]) = c(0:(length(levels(dataset[[feature]]))-1))
  if(feature != 'Churn') dataset[[feature]] = as.numeric(as.character(dataset[[feature]]))
}


# creating dummy variables for both state and area code and removing the original columns
for(unique_value in unique(dataset$state)){
  dataset[paste("state", unique_value, sep = ".")] = ifelse(dataset$state == unique_value, 1, 0)
} 

dataset$area_code= as.factor(dataset$area_code)
for(unique_value in unique(dataset$area_code)){
  dataset[paste("area_code", unique_value, sep = ".")] = ifelse(dataset$area_code == unique_value, 1, 0)
} 
dataset = within(dataset, rm(state,area_code))


# remove 'phone.number' column as it is unique for every entry and thus adding no information to the model
# length(unique(dataset$phone.number)) = 5000
dataset = within(dataset, rm(phone_number))


# splitting the dataset after preprocessing back to train_dataset and test_dataset
train_dataset = dataset[dataset$Source=='train',]
test_dataset = dataset[dataset$Source=='test',]

# Removing temporary variable source
train_dataset = within(train_dataset, rm(Source))
test_dataset = within(test_dataset, rm(Source))

# Moving Churn column to the end of dataframe
train_dataset = train_dataset[,c(colnames(train_dataset)[colnames(train_dataset)!='Churn'],'Churn')]
test_dataset = test_dataset[,c(colnames(test_dataset)[colnames(test_dataset)!='Churn'],'Churn')]


# normalizing the train and test data using preprocess function of caret package
pp = preProcess(train_dataset[-72], method=c('center','scale'))
train_dataset = predict(pp,train_dataset)
test_dataset = predict(pp, test_dataset)


# creating training and testing tasks
traintask = makeClassifTask(data= train_dataset , target= 'Churn' , positive = '1')
testtask = makeClassifTask(data= test_dataset , target= 'Churn' , positive = '1')

# creating a weight vector to for each observation to handle imbalance classes
mask = train_dataset['Churn']=='1'
obs_weight = sapply(mask, function(x) if(x==T) 9 else 1)

# creating weighted training task 
traintask_weighted = makeClassifTask(data= train_dataset , target= 'Churn' , positive = '1', weight= obs_weight)


# generic function for tuning hyperparameters using gridsearch
model_tuning <- function(algoname, algo, params_tune, traintask ){
  set.seed(42)
  gridsearch = tuneParams(algo , resampling = makeResampleDesc("CV",iters = 5L, stratify = T, predict = "both"),
                          task= traintask, par.set = params_tune,
                          measures = list(f1,tpr,ppv,auc,setAggregation(f1, train.mean),setAggregation(tpr, train.mean),setAggregation(ppv, train.mean),setAggregation(auc, train.mean)) ,
                          control = makeTuneControlGrid()
  )

  cat("\nGrid Search Report-",algoname,"\n")
  cat("Best params:\n")
  print(as.matrix(gridsearch$x))
  cat("Optimum threshold:", gridsearch$threshold)
  cat("\nEvaluation metrics for best model:Train Fold\n")
  cat("F1-Score :",gridsearch$y[5],"\n")
  cat("ROC_AUC :",gridsearch$y[8],"\n")
  cat("RECALL :",gridsearch$y[6],"\n")
  cat("PRECISION :",gridsearch$y[7],"\n")
  cat("\nEvaluation metrics for best model:Test Fold\n")
  cat("F1-Score :",gridsearch$y[1],"\n")
  cat("ROC_AUC :",gridsearch$y[4],"\n")
  cat("RECALL :",gridsearch$y[2],"\n")
  cat("ACCURACY :",gridsearch$y[3],"\n")
  return(gridsearch$x)
}


# generic function to display cross validation scores for train dataset
cross_validation <- function(algoname, algo, traintask){
  set.seed(42)
  r=resample(algo, traintask, makeResampleDesc("CV",iters=5, predict="both", stratify = T), 
             measures = list(f1,tpr,ppv,auc,setAggregation(f1, train.mean), setAggregation(tpr, train.mean),setAggregation(ppv, train.mean),setAggregation(auc, train.mean)))  
 
  cat("\nResampling Report-",algoname,"\n")
  cat("\nEvaluation metrics:Train Fold \n")
  cat("F1-Score :",r$aggr[5],"\n")
  cat("ROC_AUC :",r$aggr[8],"\n")
  cat("RECALL :",r$aggr[6],"\n")
  cat("PRECISION :",r$aggr[7],"\n")
  cat("\nEvaluation metrics:Test Fold \n")
  cat("F1-Score :",r$aggr[1],"\n")
  cat("ROC_AUC :",r$aggr[4],"\n")
  cat("RECALL :",r$aggr[2],"\n")
  cat("PRECISION :",r$aggr[3],"\n")
}


# function to generate feature importance graph
featureImportance <- function(algoname, algo, traintask){
  ftimp = data.frame(t((getFeatureImportance(train(algo, traintask)))$res))
  setDT(ftimp, keep.rownames = TRUE)[]
  colnames(ftimp)= c('Feature','Importance')
  ftimp = ftimp[order(ftimp$Importance, decreasing = T),]
  ftimp = ftimp[1:15,]
  ftimp = ftimp[order(ftimp$Importance, decreasing = F),]
  level_order = ftimp$Feature
  gg = ggplot(ftimp, aes(x=factor(Feature, level = level_order),y=Importance))+geom_col()+labs(title=algoname, x='Feature')+coord_flip()
  print(gg)
  return(ftimp$Feature)
}


# generic function to evaluate the test set using optimal parameters
Test_Set_Report <- function (algoname, algo, traintask, testtask){
  model_fit = train(algo, traintask)
  ypred = predict(model_fit , testtask)
  conf_matrix = table(test_dataset$Churn, ypred$data$response)
  recall_score = conf_matrix[2,2]/ (conf_matrix[2,1]+conf_matrix[2,2])
  precision_score = conf_matrix[2,2]/(conf_matrix[1,2]+conf_matrix[2,2])
  accuracy = sum(diag(conf_matrix))/ sum(conf_matrix)
  auc=performance(ypred,auc)
  f1= performance(ypred,f1)
  
  cat("\nTest Set Report-",algoname,"\n")
  cat("Confusion_Matrix:\n")
  print(conf_matrix)
  cat("\nEvaluation metrics:\n")
  cat("F1-Score :",f1,"\n")
  cat("ROC_AUC :",auc,"\n")
  cat("RECALL :",recall_score,"\n")
  cat("PRECISION :",precision_score,"\n")
  cat("ACCURACY :",accuracy,"\n")
  
  df = generateThreshVsPerfData(ypred, measures = list(fpr, tpr))
  gg= plotROCCurves(df)
  print(gg)
  
  return(data.frame(ypred$data$response))
}




#### LOGISTIC REGRESSION ####
logreg_model = makeLearner("classif.logreg", predict.type='prob' )

# cross validation report
cross_validation("Logistic Regression", logreg_model, traintask_weighted )

# evaluating the test set performance
ypred_logreg = Test_Set_Report("Logistic Regression", logreg_model, traintask_weighted, testtask)


#### Regularized Logistic Regression with L1 Penalty ####
classweights= c(1,6)
names(classweights)=c('0','1')
ridge_model = makeLearner("classif.LiblineaRL1LogReg", predict.type = 'prob', par.vals = list(cost=0.5, wi=classweights))

# cross validation report
cross_validation("Regularized Logistic Regression", ridge_model, traintask)

# evaluating the test set performance
ypred_ridge = Test_Set_Report("Regularized Logistic Regression", ridge_model, traintask, testtask)



#### DECISION TREE CLASSIFIER ####

# creating a learner
dectree_model = makeLearner("classif.rpart" , predict.type = "prob", par.vals= list(minbucket=50,maxdepth=4, minsplit=10), parms= list(prior=c(0.4,0.6)))

#Search for hyperparameters
params_dectree = makeParamSet(
  makeDiscreteParam("minsplit",values=c(20)),
  makeDiscreteParam("minbucket", values=c(50)),
  makeDiscreteParam("maxdepth", values=c(3)),
  makeDiscreteParam("parms", values= list(a=list(prior=c(0.4,0.6))))
)

# perform grid search to get optimal parameters
best_params_dectree = model_tuning("Decision Tree", dectree_model, params_dectree, traintask)

# cross validation report using optimal parameters
dectree_model = setHyperPars(dectree_model , par.vals = best_params_dectree)
cross_validation("Decison Tree", dectree_model, traintask)

# plot feature importance for decision trees
bestpred_dectree= featureImportance("Decision Tree",dectree_model, traintask)
colnames(bestpred_dectree)= 'Best_Features'

# evaluating the test set performance
ypred_dectree = Test_Set_Report("Decision Tree", dectree_model, traintask, testtask)




#### RANDOM FOREST CLASSIFIER ####
ranfor_model = makeLearner("classif.randomForest" , predict.type = "prob", par.vals= list(ntree= 45,mtry=35, classwt=c(0.30,0.70), nodesize= 8, maxnodes= 50, importance=T))

#Search for hyperparameters
params_ranfor = makeParamSet(
  makeDiscreteParam("ntree",values=c(55,58,63,65)),
  makeDiscreteParam('mtry', values=c(5,6,8,10)),
  makeDiscreteParam("nodesize", values=c(4,5,6)),
  makeDiscreteParam("maxnodes", values=c(43,45,47))
)

# perform grid search to get optimal parameters
best_params_ranfor = model_tuning("Random Forest", ranfor_model, params_ranfor, traintask)

# cross validation report using optimal parameters
ranfor_model = setHyperPars(ranfor_model , par.vals = best_params_ranfor)
cross_validation("Random Forest", ranfor_model, traintask)

# plot feature importance for random forest
bestpred_rf= featureImportance("Random Forest",ranfor_model, traintask)
colnames(bestpred_rf)= 'Best_Features'

# evaluating the test set performance
ypred_ranfor= Test_Set_Report("Random Forest", ranfor_model, traintask, testtask)




#### XGBOOST CLASSIFIER ####


#make learner with inital parameters
xgb_model <- makeLearner("classif.xgboost", predict.type = "prob")
xgb_model$par.vals <- list(
objective = "binary:logistic",
nrounds = 500,
eta= 0.01,
subsample= 1,
colsample_bytree= 1,
eval_metric="auc",
early_stopping_rounds=50,
verbose=1,
print_every_n = 25,
max_depth= 10,
min_child_weight = 1,
gamma = 3,
alpha = 2,
lambda = 0.1,
max_delta_step = 2
)


#Search for hyperparameters
params_xgb = makeParamSet(
  makeDiscreteParam("max_depth",values=c(5)),
  makeDiscreteParam("gamma",values=c(0)),
  makeDiscreteParam('min_child_weight', values=c(1)),
  makeDiscreteParam("subsample", values=c(1)),
  makeDiscreteParam("colsample_bytree", values=c(0.8)),
  makeDiscreteParam("max_delta_step", values=c(0.32)),
  makeDiscreteParam("alpha", values=c(0.1,0.5,1)),
  makeDiscreteParam("lambda", values=c(0.1,0.5,1))
  )

# perform grid search to get optimal parameters
best_params_xgb = model_tuning("XGBoost", xgb_model, params_xgb, traintask_weighted)

# cross validation report using optimal parameters
xgb_model = setHyperPars(xgb_model , par.vals = best_params_xgb)
cross_validation("XGBoost", xgb_model, traintask_weighted)

# plot feature importance for random forest
bestpred_xgb = data.frame(featureImportance("XGBoost",xgb_model, traintask_weighted))
colnames(bestpred_xgb)= 'Best_Features'

# evaluating the test set performance
ypred_xgb = Test_Set_Report("XGBoost", xgb_model, traintask_weighted, testtask)



### Storing the predicted results along with the actual prediction for each phone number in a csv file
FinalResult_R = cbind(FinalResult_R, ypred_xgb)
colnames(FinalResult_R)[22]= c( 'Predicted.Churn')
levels(FinalResult_R$`Predicted Churn`) = c('False', 'True')
write.csv(FinalResult_R, file="PredictedChurn_R.csv", row.names = F)
