import PlasmoGraphBase:add_node!,add_edge!,create_node,create_edge
import Base:show,print,string,getindex,copy
import JuMP:AbstractModel,setobjective,getobjectivevalue
import LightGraphs.Graph


##############################################################################
# ModelGraph
##############################################################################
#A PlasmoGraph encapsulates a pure graph object wherein nodes and edges are integers and pairs of integers respectively
"The ModelGraph Type.  Represents a system of models and the links between them"
mutable struct ModelGraph <: AbstractModelGraph
    basegraph::BasePlasmoGraph                   #model structure.  Put constraint references on edges
    linkmodel::LinkModel                         #Using composition to represent a graph as a "Model".  Someday I will figure out how to do multiple inheritance.
    serial_model::Nullable{AbstractModel}        #The internal serial model for the graph.  Returned if requested by the solve
end

ModelGraph() = ModelGraph(BasePlasmoGraph(Graph),LinkModel(),Nullable())

setobjective(graph::ModelGraph, sense::Symbol, x::JuMP.Variable) = setobjective(graph.linkmodel, sense, convert(AffExpr,x))

getlinkconstraints(model::ModelGraph) = getlinkconstraints(model.linkmodel)
getsimplelinkconstraints(model::ModelGraph) = getsimplelinkconstraints(model.linkmodel)
gethyperlinkconstraints(model::ModelGraph) = gethyperlinkconstraint(model.linkmodel)

_setobjectivevalue(graph::ModelGraph,value::Number) = graph.linkmodel.objVal = value
JuMP.getobjectivevalue(graph::ModelGraph) = graph.linkmodel.objVal

getinternaljumpmodel(graph::ModelGraph) = graph.serial_model

"""
    Get every link constraint in the graph, including subgraphs
"""
function get_all_linkconstraints(graph::ModelGraph)
    links = []
    for subgraph in getsubgraphlist(graph)
        append!(links,getlinkconstraints(subgraph))
    end
    append!(links,getlinkconstraints(graph))
    return links
end

#TODO Figure out how JuMP sets solvers now
#setsolver(model::PlasmoGraph,solver::AbstractMathProgSolver) = graph.solver = solver

##############################################################################
# Nodes
##############################################################################
mutable struct ModelNode <: AbstractModelNode
    basenode::BasePlasmoNode
    model::Nullable{AbstractModel}
    #linkconrefs::Vector{ConstraintRef}
    linkconrefs::Dict{ModelGraph,Vector{ConstraintRef}}
end

#Node constructors
#empty PlasmoNode
ModelNode() = ModelNode(BasePlasmoNode(),JuMP.Model(),Dict{ModelGraph,Vector{ConstraintRef}}())
create_node(graph::ModelGraph) = ModelNode()

getmodel(node::ModelNode) = get(node.model)
hasmodel(node::ModelNode) = get(node.model) != nothing? true: false

#Get all of the link constraints for a node in all of its graphs
getlinkconstraints(node::ModelNode) = node.linkconrefs
getlinkconstraints(graph::ModelGraph,node::ModelNode) = node.linkconrefs[graph]

is_nodevar(node::ModelNode,var::AbstractJuMPScalar) = getmodel(node) == var.m #checks whether a variable belongs to a node or edge
_is_assignedtonode(m::AbstractModel) = haskey(m.ext,:node) #check whether a model is assigned to a node

getnode(m::AbstractModel) = _is_assignedtonode(m)? m.ext[:node] : throw(error("Only node models have associated graph nodes"))
getnode(var::AbstractJuMPScalar) = var.m.ext[:node]

#get variable index on a node
getindex(node::ModelNode,sym::Symbol) = getmodel(node)[sym]

function setmodel(node::ModelNode,m::AbstractModel)
    #_updatelinks(m,nodeoredge)      #update link constraints after setting a model
    !(_is_assignedtonode(m) && getmodel(node) == m) || error("the model is already asigned to another node")
    #BREAK LINKS FOR NOW
    #If it already had a model, delete all the link constraints corresponding to that model
    # if hasmodel(node)
    #     for (graph,constraints) in getlinkconstraints(node)
    #         local_link_cons = constraints
    #         graph_links = getlinkconstraints(graph)
    #         filter!(c -> !(c in local_link_cons), graph_links)  #filter out local link constraints
    #         node.link_data = NodeLinkData()   #reset the local node or edge link data
    #     end
    # end
    node.model = m
    m.ext[:node] = node
end

#TODO
#set a model with the same variable names and dimensions as the old model on the node.
#This will not break link constraints
function resetmodel(node::ModelNode,m::AbstractModel)
    #reassign the model
    node.model = m

    #switch out variables in any connected linkconstraints
    #throw warnings if link constraints break
end

#TODO
# removemodel(nodeoredge::NodeOrEdge) = nodeoredge.attributes[:model] = nothing  #need to update link constraints

##############################################################################
# Edges
##############################################################################
struct LinkingEdge <: AbstractLinkingEdge
    baseedge::BasePlasmoEdge
    linkconrefs::Vector{ConstraintRef}
end
#Edge constructors
LinkingEdge() = LinkingEdge(BasePlasmoEdge(),JuMP.ConstraintRef[])
create_edge(graph::ModelGraph) = LinkingEdge()

function add_edge!(graph::ModelGraph,ref::JuMP.ConstraintRef)
    #TODO Make sure I can go from a constraintreference back to a link constraint
    con = LinkConstraint(ref)   #Get the Linkconstraint object so we can inspect the nodes on it

    vars = con.terms.vars
    nodes = unique([getnode(var) for var in vars])  #each var belongs to a node
    if length(nodes) == 2
        edge = add_edge!(graph,nodes[1],nodes[2])  #constraint edge connected to two nodes
        push!(edge.linkconrefs,ref)

        #Could just create a key when adding a node to a graph
        if !haskey(nodes[1].linkconrefs,graph)
            nodes[1].linkconrefs[graph] = [ref]
        else
            push!(nodes[1].linkconrefs[graph],ref)
        end

        if !haskey(nodes[2].linkconrefs,graph)
            nodes[2].linkconrefs[graph] = [ref]
        else
            push!(nodes[2].linkconrefs[graph],ref)
        end

        # push!(nodes[1].linkconrefs,ref)
        # push!(nodes[2].linkconrefs,ref)
    elseif length(nodes) > 2
        edge = add_hyper_edge!(graph,nodes...)  #constraint edge connected to more than 2 nodes
        push!(edge.linkconrefs,ref)
        for node in nodes
            if !haskey(node.linkconrefs,graph)
                node.linkconrefs[graph] = [ref]
            else
                push!(node.linkconrefs[graph],ref)
            end
            #push!(node.linkconrefs[graph],ref)
        end
    else
        throw(error("Attempted to add a link constraint for a single node"))
    end
    return edge
end

# TODO  Think of a good way to update links when swapping out models.  Might need to store variable names in NodeLinkData
# function _updatelinks(m,::AbstractModel,nodeoredge::NodeOrEdge)
#     link_cons = getlinkconstraints(nodeoredge)
#     #find variables
# end

#########################################
########################################
#Other add_node! constructors
#######################################
#Add nodes and set the model as well
function add_node!(graph::ModelGraph,m::AbstractModel)
    node = add_node!(graph)
    setmodel!(node,m)
    return node
end

#Store link constraint in the given graph.  Store a reference to the linking constraint on the nodes which it links
function addlinkconstraint(graph::ModelGraph,con::AbstractConstraint)
    isa(con,JuMP.LinearConstraint) || throw(error("Link constraints must be linear.  If you're trying to add quadtratic or nonlinear links, try creating duplicate variables and linking those"))
    ref = JuMP.addconstraint(graph.linkmodel,con)
    link_edge = add_edge!(graph,ref)  #adds edge and a contraint reference to all objects involved in the constraint
    return link_edge
end

#NOTE Figure out a good way to use containers here instead of making arrays
function addlinkconstraint{T}(graph::ModelGraph,linkcons::Array{AbstractConstraint,T})
    array_type = typeof(linkcons)  #get the array type
    array_type.parameters.length > 1? linkcons = vec(linkcons): nothing   #flatten out the constraints into a single vector

    #Check all of the constraints before I add one to the graph
    for con in linkcons
        vars = con.terms.vars
        nodes = unique([getnode(var) for var in vars])
        all(node->node in values(getnodesandedges(graph)),nodes)? nothing: error("the linkconstraint: $con contains variables that don't belong to the graph: $graph")
    end

    #Now add the constraints
    for con in linkcons
        addlinkconstraint(graph,con)
    end
end
