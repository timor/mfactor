# Generate Dot Code from ruby objects
# Include the Dot module,
# provide child_nodes() in nodes, optionally parent_nodes(), sibling_nodes()
# provide dot_label()
# optionally provide dot_record() which
# returns [record_object, position ]
module MFactor
  module DotNode
    require 'set'
    require 'ostruct'
    @@unique='1'

    def gensym(s="G")
      (s.to_s+@@unique.succ!).to_sym
    end
    # traverse from 1 node, collect all reachable nodes
    def collect(nodes=Set.new,transitions=Set.new,node_names={},records={})
      if respond_to? :dot_record
        rec, pos = dot_record
        # association: record_object => [ [ label, field_name, position ]* ]
        field_name="f#{pos}"
        port_info= OpenStruct.new(label: dot_label,
                                  name: field_name,
                                  position: position)
        if records[rec]
          records[rec].push port_info
        else
          node_names[rec]=gensym("rec")
          records[rec] = [port_info]
        end
        node_names[self]="#{node_names[rec]}:#{field_name}"
      else
        nodes.add self
        node_names[self]=gensym("node")
      end
      if respond_to? :child_nodes
        child_nodes.each do |n|
          transitions.add [self,n]
          n.collect(nodes,transitions,node_names,records) unless nodes.member? n
        end
      end
      if respond_to? :parent_nodes
        parent_nodes.each do |n|
          transitions.add [n,self]
          n.collect(nodes,transitions,node_names,records) unless nodes.member? n
        end
      end
      if respond_to? :sibling_nodes
        sibling_nodes.each do |n|
          n.collect(nodes,transitions,node_names,records) unless nodes.member? n
        end
      end
      return nodes,transitions,node_names,records
    end

    # generate dot code for one record
    def self.dot_record_code(io, record_name, portinfos)
      portinfos.sort! {|p1, p2| p1.position <=> p2.position }
      io << record_name << " [label=\"{"
      io << portinfos.map do |p|
        "<#{p.name}> #{p.label}"
        end.join(" | ")
      io << "}\"]\n"
    end

    # generate graph from this node on, reachability determined by self
    def dot_code(io)
      io << <<END
digraph test_definition {
graph [ rankdir=LR ]
node [shape=record,fontname=helvetica]
END
      nodes,transitions,node_names,records = collect
      nodes.each do |n|
        io.puts "#{node_names[n]} [label=\"#{n.dot_label}\"]"
      end
      puts records
      records.each do |rec,ports|
        DotNode.dot_record_code(io, node_names[rec],ports)
      end
      transitions.each do |s,d|
        io.puts "#{node_names[s]} -> #{node_names[d]}"
      end
      io.puts "}"
    end
  end
end
