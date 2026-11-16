#generates kano survey responses for a fictional grocery delivery app
set.seed(2026)

dir.create("data", showWarnings = FALSE)

#kano eval table
ANS <- c("Like", "Must-be", "Neutral", "Live with", "Dislike")
EV <- rbind(
  "Like"      = c("Q", "A", "A", "A", "O"),
  "Must-be"   = c("R", "I", "I", "I", "M"),
  "Neutral"   = c("R", "I", "I", "I", "M"),
  "Live with" = c("R", "I", "I", "I", "M"),
  "Dislike"   = c("R", "R", "R", "R", "Q")
)
colnames(EV) <- ANS

#for each category, list every (functional, dysfunctional) answer pair that
#maps to it, the simulation draws a category first and then a matching pair
cells <- lapply(c("A", "O", "M", "I", "R", "Q"), function(cl) {
  idx <- which(EV == cl, arr.ind = TRUE)
  data.frame(functional = ANS[idx[, "row"]], dysfunctional = ANS[idx[, "col"]])
})
names(cells) <- c("A", "O", "M", "I", "R", "Q")

#planted structure
features <- c("Live order tracking", "Approve substitutions",
              "Delivery within 30 minutes", "Loyalty rewards",
              "Recipe suggestions", "Plastic-free packaging",
              "Chat with shopper", "Price-match guarantee")

cat_names <- c("A", "O", "M", "I", "R")

#each row gives the probability that a member of the segment sees the feature
#as Attractive, One-dimensional, Must-be, Indifferent, or Reverse
make_probs <- function(rows) {
  m <- do.call(rbind, rows)
  rownames(m) <- features
  colnames(m) <- cat_names
  m / rowSums(m)
}

probs <- list(
  "Budget-focused" = make_probs(list(
    c(.05, .10, .05, .78, .02),   #live order tracking
    c(.05, .20, .65, .08, .02),   #approve substitutions
    c(.05, .05, .05, .83, .02),   #delivery within 30 minutes
    c(.08, .80, .02, .08, .02),   #loyalty rewards
    c(.05, .05, .02, .86, .02),   #recipe suggestions
    c(.04, .02, .01, .91, .02),   #plastic-free packaging
    c(.04, .04, .04, .86, .02),   #chat with shopper
    c(.05, .78, .10, .05, .02)    #price-match guarantee
  )),
  "Convenience-seekers" = make_probs(list(
    c(.80, .10, .03, .05, .02),
    c(.05, .20, .65, .08, .02),
    c(.05, .84, .06, .03, .02),
    c(.05, .05, .02, .86, .02),
    c(.05, .04, .01, .88, .02),
    c(.04, .02, .01, .91, .02),
    c(.76, .08, .03, .11, .02),
    c(.05, .05, .03, .85, .02)
  )),
  "Sustainability-minded" = make_probs(list(
    c(.05, .05, .03, .85, .02),
    c(.05, .15, .20, .58, .02),
    c(.03, .03, .02, .90, .02),
    c(.05, .05, .02, .86, .02),
    c(.80, .08, .02, .08, .02),
    c(.08, .84, .04, .03, .01),
    c(.04, .04, .02, .88, .02),
    c(.04, .04, .02, .88, .02)
  ))
)

segment_share <- c("Budget-focused" = 0.36,
                   "Convenience-seekers" = 0.40,
                   "Sustainability-minded" = 0.24)

N     <- 400    #number of synthetic respondents
NOISE <- 0.04   #chance that an answer pair is contradictory (category Q)

#simulate
segment_true <- sample(names(segment_share), N, replace = TRUE, prob = segment_share)

out <- vector("list", N * length(features))
k <- 0
for (i in seq_len(N)) {
  seg <- segment_true[i]
  for (f in features) {
    cl <- sample(cat_names, 1, prob = probs[[seg]][f, ])
    if (runif(1) < NOISE) cl <- "Q"
    pool <- cells[[cl]]
    pair <- pool[sample(nrow(pool), 1), ]
    k <- k + 1
    out[[k]] <- data.frame(respondent_id = i, feature = f,
                           functional = pair$functional,
                           dysfunctional = pair$dysfunctional)
  }
}
responses <- do.call(rbind, out)

truth <- data.frame(respondent_id = seq_len(N), segment_true = segment_true)

write.csv(responses, "data/synthetic_responses_long.csv", row.names = FALSE)
write.csv(truth, "data/synthetic_truth.csv", row.names = FALSE)

cat("Wrote", nrow(responses), "synthetic answer pairs for", N, "synthetic respondents.\n")
cat("Planted segment sizes:\n")
print(table(segment_true))

