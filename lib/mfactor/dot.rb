# Generate Dot Code from ruby objects
# Include the Dot module,
# provide child_nodes() in nodes, optionally parent_nodes(),
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
    def collect(nodes=Set.new,transitions=Set.new,node_names={},records=Set.new)
      if dot_record
        rec, pos = dot_record
        # association: record_object => [ [ label, field_name, position ]* ]
        field_name="f#{pos}"
        port_info= OpenStruct.new(label: dot_label,
                                  name: field_name,
                                  position: position)
        if records[rec]
          record[rec].push port_info
        else
          node_names[rec]=gensym("rec")
          record[rec] = [port_info]
        end
        node_names[n]="#{@node_names[rec]}:#{field_name}"
      else
        nodes.add self
        node_names[n]=gensym("node")
      end
      if responds_to :child_nodes
        child_nodes.each do |n|
          transitions.add [self,n]
          n.reachable_nodes(nodes,transitions) unless nodes.member? n
        end
      end
      if responds_to :parent_nodes
        parent_nodes.each do |n|
          transitions.add [n,self]
          n.reachable_nodes(nodes,transitions) unless nodes.member? n
        end
      end
      return nodes,transitions
    end

    # generate dot code for one record
    def self.dot_record_code(io, record_name, portinfos)
      portinfos.sort! {|p1, p2| p1.position <=> p2.position }
      io << record_name << " [label=\"{"
      io << portinfos.map do |p|
        "<#{p.name}> #{p.label}"
        end.join(" | ")
      io << "}\n"
    end

    # generate graph from this node on, reachability determined by self
    def dot_code(io)
      io << <<END
digraph #{name}_definition {
graph [ rankdir=LR ]
node [shape=record,fontname=helvetica]
END
      nodes,transitions,node_names,records = collect
      nodes.each do |n|
        io.puts "#{@node_names[n]} [label=\"#{n.dot_label}\"]}"
      end
      records.each do |r|
        DotNode.dot_record_code(io, @node_names[r],records[r])
      end
      transitions.each do |s,d|
        io.puts "#{@node_names[s]} -> #{@node_names[t]}"
      end
      io.puts "}"
    end
  end
end
