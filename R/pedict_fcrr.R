predict.fcrr <- function(object, newdata, getBootstrapVariance = TRUE,
                         var.control = varianceControl(B = 100, useMultipleCores = FALSE),
                         type = "none", alpha = 0.05, tL = NULL, tU = NULL, ...){
  
  ## Error checking
  if(class(object) != "fcrr") {
    stop("Object 'fit' must be of class fcrr")
  }
  
  if(is.null(object$breslowJump)) {
    stop("Breslow jumps were not calculated. Please re-run model with 'getBreslowJumps = TRUE'")
  }
  
  if(is.null(object$df)) {
    stop("Ordered data frame not returned. Please re-run model with 'returnDataFrame = TRUE'")
  }
  
  if(!(type %in% c("none", "bands", "interval"))) {
    type = "none"
    warning("type is incorrectly specified. Valid options are 'bands', 'interval', 'none'.
            Set to 'none'")
  }
  
  if(alpha <= 0 | alpha >= 1) {
    alpha = 0.05
    warning("alpha is incorrectly specified. Set to 0.05")
  }
  
  
  if(is.null(tL)) tL <- min(object$uftime)
  if(is.null(tU)) tU <- max(object$uftime)
  
  if(tL <= 0 | tL >= max(object$uftime)) {
    tL <- min(object$uftime)
    warning("tL is incorrectly specified (can not be nonpositive or larger than largest observed event time.
            Set to smallest observed event time")
  }
  
  if(tU <= 0 | tU <= min(object$uftime)) {
    tU <- max(object$uftime)
    warning("tU is incorrectly specified (can not be nonpositive or smaller than smallest observed event time.
            Set to largest observed event time")
  }
  
  min.idx = min(which(object$uftime >= tL))
  max.idx = max(which(object$uftime <= tU))
  
  if (length(object$coef) == length(newdata)) {
    CIF.hat <- cumsum(exp(sum(newdata * object$coef)) * object$breslowJump[, 2]) #This is cumulative hazard
    CIF.hat <- 1 - exp(-CIF.hat)
  } else {
    stop("Parameter dimension of 'newdata' does not match dimension of '$coef' from object.")
  }
  
  res  <- data.frame(ftime = object$uftime, CIF = CIF.hat, lower = NA, upper = NA)
  #Get SD via bootstrap
  if(getBootstrapVariance) {
    controls = var.control
    if (!missing(controls))
      controls[names(controls)] <- controls
    B        <- controls$B
    seed     <- controls$seed
    mcores   <- controls$mcores
    # Are we using multiple cores (parallel) or not
    if(mcores) `%mydo%` <- `%dopar%`
    else          `%mydo%` <- `%do%`
    
    i <- NULL  #this is only to trick R CMD check,
    
    set.seed(seed)
    seeds = sample.int(2^25, B, replace = FALSE)
    CIF.boot <- numeric()
    ftime <- object$df$ftime
    fstatus <- object$df$fstatus
    n <- length(ftime)
    X <- as.matrix(object$df[, -(1:2)]) #Remove event time and censoring indicator
    
    CIF.boot <- foreach(i = seeds, .combine = 'rbind', .packages = "fastcmprsk") %mydo% {
      set.seed(i)
      bsamp  <- sample(n, n, replace = TRUE) #Bootstrap sample index
      fit.bs <- fastCrr(Crisk(ftime[bsamp], fstatus[bsamp]) ~ X[bsamp, ], variance = FALSE, ...)
      CIF.bs <- 1 - exp(-cumsum(exp(sum(newdata * fit.bs$coef)) * fit.bs$breslowJump[, 2]))
      return(evalstep(fit.bs$breslowJump$time,
                      stepf = CIF.bs,
                      subst = 1E-16,
                      newtime = object$uftime))
      rm(fit.bs)
    }
    #colnames(CIF.boot) <- round(object$uftime, 3)
    
    #Variance Stabalization: f(x) = log(-log(x))
    CIF.hat  <- log(-log(CIF.hat))
    CIF.boot <- log(-log(CIF.boot))
    CIF.sd <- apply(CIF.boot, 2, sd)
    if(type == "bands") {
      #If interval type is confidence band.
      #Find Pr(sup_[tL, tU] |Fhat - F| / sd(F) <= C) = 1 - alpha / 2
      sup    <- apply(CIF.boot, 1, function(x) max((abs(x - CIF.hat) / CIF.sd)[min.idx:max.idx]))
      z.stat <- quantile(sup, 1 - alpha / 2) #Find bootstrap quantile of sup|Fhat - F|
      llim   <- CIF.hat + z.stat * CIF.sd
      ulim   <- CIF.hat - z.stat * CIF.sd
      res  <- data.frame(ftime = object$uftime, CIF = exp(-exp(CIF.hat)), lower = exp(-exp(llim)), upper = exp(-exp(ulim)))
    } else if (type == "interval") {
      #If interval type if pointwise
      llim   <- CIF.hat + qnorm(1 - alpha / 2) * CIF.sd
      ulim   <- CIF.hat - qnorm(1 - alpha / 2) * CIF.sd
      res  <- data.frame(ftime = object$uftime, CIF = exp(-exp(CIF.hat)), lower = exp(-exp(llim)), upper = exp(-exp(ulim)))
    }
  }
  #Subset corresponding to tL and tU
  res <- subset(res, res$ftime >= tL & res$ftime <= tU)
  class(res) <- "predict.fcrr"
  res$type <- type
  return(res)
}