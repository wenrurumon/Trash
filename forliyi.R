
rm(list=ls())
library(data.table)
library(dplyr)
library(keras)
library(pROC)
setwd('/Users/wenrurumon/Documents/posdoc/liyi')
raw <- readRDS(('baseline.impute.rds'))

############################################################################################################
############################################################################################################

raw  <- fread("2019HA_Composite_PCs.csv") %>% select(-AMS.2013)
raw <- apply(raw,2,function(x){(x-min(x))/(max(x)-min(x))}) %>% as.data.frame

#Sigmoid Network

model.sigmoid <- function(X,Y,epoch=100){
  X <- as.matrix(X)
  Y <- as.matrix(Y)
  l1 <- layer_input(shape=ncol(X))
  l2 <- layer_dense(l1,8,activation='relu') %>% layer_dropout(rate=0.3)
  # l3 <- layer_dense(l2,8,activation='relu') %>% layer_dropout(rate=0.3)
  l4 <- layer_dense(l2,1,activation='sigmoid') 
  model <- keras_model(l1,l4)
  model %>% compile(loss = "mae", optimizer = "adam")
  system.time(temp <- model %>% fit(x = X,y = Y,batch = 128,epochs = 1000,verbose = 0))
  loss <- Inf
  itv <- 0
  system.time(temp <- model %>% fit(x = X,y = Y,batch = 128,epochs = 1000,verbose = 0))
  print(paste(loss,mean(temp$metrics$loss),itv<-itv+1,'first epochs',Sys.time(),sep=', '))
  while(mean(temp$metrics$loss)<loss){
    loss <- mean(temp$metrics$loss)
    system.time(temp <- model %>% fit(x = X,y = Y,batch = 128,epochs = epoch,verbose = 0))
    print(paste(loss,mean(temp$metrics$loss),itv<-itv+1,'new epoch',Sys.time(),sep=', '))
    if(mean(temp$metrics$loss)>loss){
      system.time(temp <- model %>% fit(x = X,y = Y,batch = 128,epochs = epoch,verbose = 0))
      print(paste(loss,mean(temp$metrics$loss),itv<-itv+1,'2nd epoch',Sys.time(),sep=', '))
    }
    if(mean(temp$metrics$loss)>loss){
      system.time(temp <- model %>% fit(x = X,y = Y,batch = 128,epochs = epoch,verbose = 0))
      print(paste(loss,mean(temp$metrics$loss),itv<-itv+1,'3rd epoch',Sys.time(),sep=', '))
    }
  }
  return(model)
}

set.seed(123); 
sel <- list(sample(1:nrow(raw),0.7*nrow(raw)),
            sample(1:nrow(raw),0.7*nrow(raw)),
            sample(1:nrow(raw),0.7*nrow(raw)),
            sample(1:nrow(raw),0.7*nrow(raw)),
            sample(1:nrow(raw),0.7*nrow(raw)))
train <- lapply(sel,function(s){raw[s,,drop=F]})
test <- lapply(sel,function(s){raw[-s,,drop=F]})
model <- lapply(train,function(datai){
  Y <- select(datai,AMS.2018) %>% as.matrix
  X <- select(datai,-AMS.2018) %>% as.matrix
  model.sigmoid(X,Y,epoch=1000)
})
rlt <- sapply(model,function(modeli){
  sapply(c(train,test),function(datai){
    predi <- modeli %>% predict(as.matrix(datai[,-1]))
    # predi <- (predi>0.5)+0
    roc(datai[[1]]~predi)$auc
  })
})
dimnames(rlt) <- list(paste0(rep(c('train','test'),each=length(sel)),c(1:length(sel),1:length(sel))),
                      paste0('model',1:length(sel)))
rlt

#Xgboost

rm(list=ls())
library(xgboost)
library(data.table)
library(dplyr)
library(keras)
library(pROC)
setwd('/Users/wenrurumon/Documents/posdoc/liyi')
raw  <- fread("2019HA_Composite_PCs.csv") %>% select(-AMS.2013) %>% as.matrix
raw <- apply(raw,2,function(x){(x-min(x))/(max(x)-min(x))})
raw <- raw[,sapply(strsplit(colnames(raw),'\\.'),function(x){x[[1]]})%in%c('AMS','M1','M2')]

Y <- raw[,1]
X <- raw[,-1]
raw.model <- apply(X,2,function(x){
  datax <- data.frame(y=Y,x=x)
  modelx <- MASS::lda(y~.,data=datax)
  rltx <- predict(modelx)$posterior[,2]  
  list(model=modelx,rlt=rltx)
  # list(model=modelx,rlt=x)
})
raw2 <- sapply(1:ncol(X),function(i){raw.model[[i]]$rlt})
colnames(raw2) <- colnames(raw)[-1]
raw2 <- do.call(cbind,lapply(1:ncol(raw2),function(i){
  do.call(cbind,lapply(i:ncol(raw2),function(j){
    x <- cbind(raw2[,i]*raw2[,j])
    colnames(x) <- paste(colnames(raw2)[i],colnames(raw2)[j],sep='*')
    x
  }))
}))
raw2 <- cbind(Y,raw2)
test <- function(i){
  set.seed(i) 
  sel <- sample(1:nrow(raw),0.7*nrow(raw))
  train <- raw2[sel,]; test <- raw2[-sel,]
  dtrain <- xgb.DMatrix(train[,-1], label = train[,1])
  dtest <- xgb.DMatrix(test[,-1], label = test[,1])
  watchlist <- list(train = dtrain, eval = dtest)
  param <- list(max_depth = 2, eta = 1, verbose = 0, nthread = 2,
                objective = "binary:logistic", eval_metric = "auc")
  bst <- xgb.train(param, dtrain, nrounds = 2, watchlist)
  roc(test[,1],as.numeric(predict(bst,newdata=dtest)))$auc
}
test <- sapply(1:100,test)
hist(test)
summary(test)
test1 <- test

#############

xgb <- function(raw,sel1=1:nrow(raw),sel2=sel1){
  train <- raw[sel1,]; test <- raw[sel2,]
  dtrain <- xgb.DMatrix(train[,-1,drop=F], label = train[,1])
  dtest <- xgb.DMatrix(test[,-1,drop=F], label = test[,1])
  watchlist <- list(train = dtrain, eval = dtest)
  param <- list(max_depth = 2, eta = 1, verbose = 0, nthread = 2,
                objective = "binary:logistic", eval_metric = "auc")
  bst <- xgb.train(param, dtrain, nrounds = 2, watchlist)
  list(model=bst,auc=roc(test[,1],as.numeric(predict(bst,newdata=dtest)))$auc)
}
vsel <- sapply(2:ncol(raw2),function(i){
  sapply(1:100,function(j){
    set.seed(j);sel <- sample(1:nrow(raw2),0.7*nrow(raw2))
    xgb(cbind(raw2[,1],raw2[,i]),sel,(1:nrow(raw2))[-sel])$auc
  })
})
raw0 <- cbind(raw2[,1],raw2[,-1][,colMeans(vsel)>quantile(vsel,0.9)])
test <- sapply(1:1000,function(j){
  set.seed(j);sel <- sample(1:nrow(raw2),0.7*nrow(raw2))
  xgb(raw0,sel,(1:nrow(raw2))[-sel])$auc
})
summary(test)
