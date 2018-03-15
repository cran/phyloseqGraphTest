## ---- echo = FALSE-------------------------------------------------------
library(knitr)
opts_chunk$set(fig.width = 6, fig.height = 4)

## ------------------------------------------------------------------------
library(phyloseq)
unlist(distanceMethodList)

## ------------------------------------------------------------------------
library(ggplot2)
# not necessary, but I like the white background with ggplot
theme_set(theme_bw())
library(phyloseqGraphTest)
data(enterotype)
enterotype

## ------------------------------------------------------------------------
gt = graph_perm_test(enterotype,
                     sampletype = "SeqTech",
                     distance = "jaccard",
                     type = "knn",
                     knn = 1)
gt

## ------------------------------------------------------------------------
plot_test_network(gt)

## ------------------------------------------------------------------------
plot_permutations(gt)

