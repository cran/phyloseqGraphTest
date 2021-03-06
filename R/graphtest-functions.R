

#' Performs graph-based permutation tests
#'
#' Performs graph-based tests for one-way designs.
#'
#' @param physeq A phyloseq object.
#' @param sampletype A string giving the column name of the sample to
#' be tested. This should be a factor with two or more levels.
#' @param grouping Either a string with the name of a sample data
#' column or a factor of length equal to the number of samples in
#' physeq. These are the groups of samples whose labels should be
#' permuted and are used for repeated measures designs. Default is no
#' grouping (each group is of size 1).
#' @param distance A distance, see \code{\link[phyloseq]{distance}} for a
#' list of the possible methods.
#' @param type One of "mst", "knn", "threshold". If "mst", forms the
#' minimum spanning tree of the sample points. If "knn", forms a
#' directed graph with links from each node to its k nearest
#' neighbors. If "threshold", forms a graph with edges between every
#' pair of samples within a certain distance.
#' @param max.dist For type "threshold", the maximum distance between
#' two samples such that we put an edge between them.
#' @param knn For type "knn", the number of nearest neighbors.
#' @param keep.isolates In the returned network, keep the unconnected
#' points?
#' @param nperm The number of permutations to perform.
#' @param nedges If using "threshold.nedges", the number of edges to use.
#'
#'
#' @importFrom igraph graph.adjacency minimum.spanning.tree
#' get.edgelist V<- E<- V E induced_subgraph
#' @import phyloseq
#' @import ggplot2
#' @import ggnetwork
#' 
#' @return A list with the observed number of pure edges, the vector
#' containing the number of pure edges in each permutation, the
#' permutation p-value, the graph used for testing, and a vector with
#' the sample types used for the test.
#' @examples
#' library(phyloseq)
#' data(enterotype)
#' gt = graph_perm_test(enterotype, sampletype = "SeqTech", type = "mst")
#' gt
#' @export
graph_perm_test = function(physeq, sampletype, grouping = 1:nsamples(physeq),
    distance = "jaccard", type = c("mst", "knn", "threshold.value", "threshold.nedges"),
    max.dist = .4, knn = 1, nedges = nsamples(physeq), keep.isolates = TRUE, nperm = 499) {
    type = match.arg(type)
    # make the network
    d = distance(physeq, method = distance, type = "samples")
    if(!validGrouping(sample_data(physeq), sampletype, grouping)) {
        stop("Not a valid grouping, all values of sampletype must
              be the same within each level of grouping")
    }
    switch(type,
           "threshold.value" = {
               neighbors = as.matrix(d) <= max.dist
               diag(neighbors) = 0
               net = graph.adjacency(neighbors, mode = "undirected", add.colnames = "name")   
           },
           "threshold.nedges" = {
               threshold = sort(as.vector(d))[nedges]
               neighbors = as.matrix(d) <= threshold
               diag(neighbors) = 0
               net = graph.adjacency(neighbors, mode = "undirected", add.colnames = "name")
           },
           "knn" = {
               neighbors = t(apply(as.matrix(d),1, function(x) {
                   r = rank(x)
                   nvec = ((r > 1) & (r < (knn + 2))) + 0
               }))
               neighbors = neighbors + t(neighbors)
               net = graph.adjacency(neighbors, mode = "undirected",
                   add.colnames = "name", weighted = TRUE)
           },
           "mst" = {
               gr = graph.adjacency(as.matrix(d), mode = "undirected", weighted = TRUE,
                   add.colnames = "name")
               net = minimum.spanning.tree(gr, algorithm = "prim")
           }           
           )
    el = get.edgelist(net)
    sampledata = data.frame(sample_data(physeq))
    elTypes = el
    elTypes[,1] = sampledata[el[,1], sampletype]
    elTypes[,2] = sampledata[el[,2], sampletype]
    observedPureEdges = apply(elTypes, 1, function(x) x[1] == x[2])
    edgeType = sapply(observedPureEdges, function(x) if(x) "pure" else "mixed")
    # set these attributes for plotting later
    if(is.factor(sampledata[,sampletype]))
        V(net)$sampletype = as.character(sampledata[,sampletype])
    else
        V(net)$sampletype = sampledata[,sampletype]
    E(net)$edgetype = edgeType
    
    # find the number of pure edges for the non-permuted data
    nobserved = sum(observedPureEdges)
    origSampleData = sampledata[,sampletype]
    names(origSampleData) = rownames(sampledata)
    # find the permutation distribution of the number of pure edges
    permvec = numeric(nperm)
    for(i in 1:nperm) {
        sampledata[,sampletype] = permute(sampledata, grouping, sampletype)
        elTypes = el
        elTypes[,1] = sampledata[el[,1], sampletype]
        elTypes[,2] = sampledata[el[,2], sampletype]
        permPureEdges = apply(elTypes, 1, function(x) x[1] == x[2])
        permvec[i] = sum(permPureEdges)
    }
    pval = (sum(permvec >= nobserved) + 1) / (nperm + 1)
    if(!keep.isolates) {
        degrees = igraph::degree(net)
        net = igraph::induced_subgraph(net, which(degrees > 0))
    }
    out = list(observed = nobserved, perm = permvec, pval = pval,
               net = net, sampletype = origSampleData, type = type)
    class(out) = "psgraphtest"
    return(out)
}

#' Print psgraphtest objects
#' @param x \code{psgraphtest} object.
#' @param ... Not used
#' @method print psgraphtest
#' @export
print.psgraphtest <- function(x, ...) {
    cat("Output from graph_perm_test\n")
    cat("---------------------------\n")
    cat(paste("Observed test statistic: ", x$observed, " pure edges", "\n", sep = ""))
    cat(paste(nrow(get.edgelist(x$net)), " total edges in the graph", "\n", sep = ""))
    cat(paste("Permutation p-value: ", x$pval, "\n", sep = ""))
}

#' Permute labels
#'
#' Permutes sample labels, respecting repeated measures.
#'
#' @param sampledata Data frame describing the samples.
#' @param grouping Grouping for repeated measures.
#' @param sampletype The sampletype used for testing (a column of sampledata).
#' @return A permuted set of labels where the permutations are done
#'     over the levels of grouping.
#' @keywords internal
permute = function(sampledata, grouping, sampletype) {
    if(length(grouping) != nrow(sampledata)) {
        grouping = sampledata[,grouping]
    }
    x = as.character(sampledata[,sampletype])
    # gives the original mapping between grouping variables and sampletype
    labels = tapply(x, grouping, function(x) x[1])
    # permute the labels of the groupings
    names(labels) = sample(names(labels))
    return(labels[as.character(grouping)])
}

#' Check for valid grouping
#'
#' Grouping should describe a repeated measures design, so this
#' function tests whether all of the levels of grouping have the same
#' value of sampletype.
#'
#' @param sd Data frame describing the samples.
#' @param sampletype The sampletype used for testing.
#' @param grouping Grouping for repeated measures.
#' @return TRUE or FALSE for valid or invalid grouping.
#' @keywords internal
validGrouping = function(sd, sampletype, grouping) {
    if(!(sampletype %in% colnames(sd))) {
        stop("\'sampletype\' must be a column names of the sample data")
    }
    if(!(all(grouping %in% colnames(sd))) && (length(grouping) != nrow(sd))) {
        stop("\'grouping\' must be either a column name of the sample data
             or a vector with number of elements equal to the number of samples")
    }
    sd = data.frame(sd)
    if(length(grouping) != nrow(sd)) {
        grouping = sd[,grouping]
    }
    valid = all(tapply(sd[,sampletype], grouping, FUN = function(x)
        length(unique(x)) == 1))
    return(valid)
}

#' Plots the graph used for testing
#'
#' When using the graph_perm_test function, a graph is created. This
#' function will plot the graph used for testing with nodes colored by
#' sample type and edges marked as pure or mixed.
#'
#' @param graphtest The output from graph_perm_test.
#' @return A ggplot object created by ggnetwork.
#' @examples
#' library(phyloseq)
#' data(enterotype)
#' gt = graph_perm_test(enterotype, sampletype = "SeqTech")
#' plot_test_network(gt)
#' @export
plot_test_network = function(graphtest) {
    if(graphtest$type == "mst")
        layout = igraph::layout_(graphtest$net, igraph::with_kk())
    else
        layout = igraph::layout_(graphtest$net, igraph::with_fr())
    ggplot(graphtest$net,
      aes_string(x = "x", y = "y", xend = "xend", yend = "yend"), layout = layout) +
      geom_edges(aes_string(linetype = "edgetype")) +
      geom_nodes(aes_string(color = "sampletype")) +
      scale_linetype_manual(values = c(3,1)) + theme_blank()
}


#' Plots the permutation distribution
#'
#' Plots a histogram of the permutation distribution of the number of
#' pure edges and a mark showing the observed number of pure edges. 
#'
#' @param graphtest The output from graph_perm_test.
#' @param bins The number of bins to use for the histogram.
#' @importFrom utils packageVersion
#' @return A ggplot object.
#' @examples
#' library(phyloseq)
#' data(enterotype)
#' gt = graph_perm_test(enterotype, sampletype = "SeqTech")
#' plot_permutations(gt)
#' @export
plot_permutations = function(graphtest, bins = 30) {
    p = qplot(graphtest$perm, geom = "histogram", bins = bins)
    if(packageVersion("ggplot2") >= "2.2.1.9000") {
        ymax = max(ggplot_build(p)$layout$panel_scales_y[[1]]$get_limits())
    } else {
        ymax = ggplot_build(p)$layout$panel_ranges[[1]][["y.range"]][2]
    }
    p + geom_segment(aes(x = graphtest$observed, y = 0,
                         xend = graphtest$observed, yend = ymax / 10), color = "red") +
        geom_point(aes(x = graphtest$observed, y = ymax / 10), color = "red") +
        xlab("Number of pure edges")                         
}
