library(ggplot2)

dir.create("figures", showWarnings = FALSE)
dir.create("data", showWarnings = FALSE)

#load and classify
ANS <- c("Like", "Must-be", "Neutral", "Live with", "Dislike")
EV <- rbind(
  "Like"      = c("Q", "A", "A", "A", "O"),
  "Must-be"   = c("R", "I", "I", "I", "M"),
  "Neutral"   = c("R", "I", "I", "I", "M"),
  "Live with" = c("R", "I", "I", "I", "M"),
  "Dislike"   = c("R", "R", "R", "R", "Q")
)
colnames(EV) <- ANS

df <- read.csv("data/synthetic_responses_long.csv", stringsAsFactors = FALSE)
df$kano <- EV[cbind(match(df$functional, ANS), match(df$dysfunctional, ANS))]

cats <- c("A", "O", "M", "I", "R", "Q")
df$kano <- factor(df$kano, levels = cats)
features <- unique(df$feature)

#feature summary:
#better = share of respondents who would be more satisfied with the feature.
#worse  = share who would be less satisfied without it (shown as a negative).
#questionable (Q) and reverse (R) answers are left out of both denominators.
summarize_features <- function(d) {
  tab <- table(factor(d$feature, levels = features), d$kano)
  denom <- tab[, "A"] + tab[, "O"] + tab[, "M"] + tab[, "I"]
  data.frame(
    feature = rownames(tab),
    A = tab[, "A"], O = tab[, "O"], M = tab[, "M"], I = tab[, "I"],
    R = tab[, "R"], Q = tab[, "Q"],
    modal = apply(tab[, c("A", "O", "M", "I")], 1, function(x) names(which.max(x))),
    better = round((tab[, "A"] + tab[, "O"]) / denom, 3),
    worse = round(-(tab[, "O"] + tab[, "M"]) / denom, 3),
    row.names = NULL
  )
}

overall <- summarize_features(df)
write.csv(overall, "data/feature_summary_overall.csv", row.names = FALSE)
cat("\nOverall feature summary (all respondents pooled):\n")
print(overall)

#better v worse chart
plot_bw <- function(s, title) {
  # Use ggrepel to keep labels from overlapping when it is installed.
  label_layer <- if (requireNamespace("ggrepel", quietly = TRUE)) {
    ggrepel::geom_text_repel(size = 3, box.padding = 0.5, min.segment.length = 0)
  } else {
    geom_text(vjust = -0.9, size = 3, check_overlap = TRUE)
  }
  ggplot(s, aes(x = -worse, y = better, label = feature)) +
    geom_vline(xintercept = mean(-s$worse), linetype = "dashed", colour = "grey60") +
    geom_hline(yintercept = mean(s$better), linetype = "dashed", colour = "grey60") +
    geom_point(size = 3, colour = "#1F3864") +
    label_layer +
    scale_x_continuous(limits = c(0, 1), expand = expansion(mult = c(0.02, 0.1))) +
    scale_y_continuous(limits = c(0, 1), expand = expansion(mult = c(0.02, 0.1))) +
    labs(title = title,
         subtitle = "SYNTHETIC DATA: simulated respondents, not real customers",
         x = "Dissatisfaction if the feature is missing",
         y = "Satisfaction if the feature is present") +
    theme_minimal(base_size = 11)
}

ggsave("figures/better_worse_overall.png",
       plot_bw(overall, "Feature priorities, all respondents pooled"),
       width = 8, height = 6, dpi = 150)

#cluster respondents without planted labels
ids <- sort(unique(df$respondent_id))
build_row <- function(g) {
  g <- g[match(features, g$feature), ]
  c(sapply(c("A", "O", "M"), function(k) as.numeric(as.character(g$kano) == k)))
}
X <- t(sapply(ids, function(i) build_row(df[df$respondent_id == i, ])))
colnames(X) <- as.vector(outer(features, c("A", "O", "M"), paste, sep = "_"))

#choose the number of clusters by looking at the within-cluster variation
set.seed(1)
wss <- sapply(2:6, function(k) kmeans(X, centers = k, nstart = 25)$tot.withinss)
elbow <- data.frame(k = 2:6, wss = wss)
ggsave("figures/cluster_elbow.png",
       ggplot(elbow, aes(k, wss)) + geom_line() + geom_point() +
         labs(title = "Choosing the number of clusters",
              subtitle = "SYNTHETIC DATA",
              x = "Number of clusters", y = "Total within-cluster sum of squares") +
         theme_minimal(base_size = 11),
       width = 6, height = 4, dpi = 150)

K <- 3   #chosen from the elbow chart; confirm that the bend sits at 3
set.seed(1)
fit <- kmeans(X, centers = K, nstart = 50)
clusters <- data.frame(respondent_id = ids, cluster = fit$cluster)
df <- merge(df, clusters, by = "respondent_id")

#compare with the planted truth and profile the clusters
truth <- read.csv("data/synthetic_truth.csv", stringsAsFactors = FALSE)
cmp <- merge(clusters, truth, by = "respondent_id")

adjusted_rand <- function(x, y) {
  tab <- table(x, y)
  n <- sum(tab)
  comb2 <- function(v) sum(choose(v, 2))
  a <- comb2(tab); b <- comb2(rowSums(tab)); c2 <- comb2(colSums(tab))
  expected <- b * c2 / choose(n, 2)
  (a - expected) / (0.5 * (b + c2) - expected)
}

cat("\nClusters found versus planted segments:\n")
print(table(planted = cmp$segment_true, cluster = cmp$cluster))
cat("\nAdjusted Rand index (1 = perfect recovery, 0 = chance):",
    round(adjusted_rand(cmp$segment_true, cmp$cluster), 3), "\n")

profiles <- do.call(rbind, lapply(sort(unique(df$cluster)), function(k) {
  s <- summarize_features(df[df$cluster == k, ])
  s$cluster <- k
  s$n_respondents <- sum(clusters$cluster == k)
  s
}))
write.csv(profiles, "data/feature_summary_by_cluster.csv", row.names = FALSE)

cat("\nModal Kano category for each feature, by cluster:\n")
print(reshape(profiles[, c("feature", "cluster", "modal")],
              idvar = "feature", timevar = "cluster", direction = "wide"))

#satisfaction heatmap
heat <- ggplot(profiles, aes(x = factor(cluster), y = feature, fill = better)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.2f", better), colour = better > 0.5),
            size = 3, show.legend = FALSE) +
  scale_fill_gradient(low = "#EEF2F8", high = "#1F3864", limits = c(0, 1)) +
  scale_colour_manual(values = c("TRUE" = "white", "FALSE" = "black")) +
  labs(title = "Satisfaction gain from each feature, by discovered segment",
       subtitle = "SYNTHETIC DATA: simulated respondents, not real customers",
       x = "Discovered cluster", y = NULL, fill = "Better") +
  theme_minimal(base_size = 11)
ggsave("figures/cluster_heatmap.png", heat, width = 8, height = 5, dpi = 150)

#dissatisfaction heatmap
heat_worse <- ggplot(profiles, aes(x = factor(cluster), y = feature, fill = -worse)) +
  geom_tile(colour = "white") +
  geom_text(aes(label = sprintf("%.2f", -worse), colour = -worse > 0.5),
            size = 3, show.legend = FALSE) +
  scale_fill_gradient(low = "#FBEFEA", high = "#8A2D0F", limits = c(0, 1)) +
  scale_colour_manual(values = c("TRUE" = "white", "FALSE" = "black")) +
  labs(title = "Dissatisfaction if each feature is missing, by discovered segment",
       subtitle = "SYNTHETIC DATA: simulated respondents, not real customers",
       x = "Discovered cluster", y = NULL, fill = "Worse") +
  theme_minimal(base_size = 11)
ggsave("figures/cluster_heatmap_worse.png", heat_worse, width = 8, height = 5, dpi = 150)

#test whether the category mix differs by cluster for each feature
cat("\nChi-square tests of Kano category versus cluster (simulated p-values):\n")
set.seed(1)
tests <- do.call(rbind, lapply(features, function(f) {
  d <- df[df$feature == f, ]
  tb <- table(d$kano, d$cluster)
  tb <- tb[rowSums(tb) > 0, , drop = FALSE]   # drop categories nobody chose
  tt <- chisq.test(tb, simulate.p.value = TRUE, B = 5000)
  data.frame(feature = f, chi_sq = round(unname(tt$statistic), 1), p_value = tt$p.value)
}))
print(tests)

cat("\nDone. Figures are in figures/ and tables are in data/.\n")
