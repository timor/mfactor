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
    def add_child(*clist)
      puts "child"
      @child_nodes ||= []
      clist.each do |c|
        unless @child_nodes.member? c
          @child_nodes.push c
          c.add_parent self
        end
      end
    end
    def add_parent(*clist)
      puts "parent"
      @parent_nodes ||= []
      clist.each do |c|
        unless @parent_nodes.member? c
          @parent_nodes.push c
          c.add_child self
        end
      end
    end
    def add_sibling(*clist)
      puts "sibling"
      @sibling_nodes ||= []
      clist.each do |c|
        unless @sibling_nodes.member? c
          @sibling_nodes.push c
          c.add_sibling self
        end
      end
    end
    def in_record(r)
      puts "in_record"
      @record = r
    end
    def record
      @record||=nil
      @record
    end
    def gensym(s="G")
      (s.to_s+@@unique.succ!).to_sym
    end
    module_function :gensym
    def node_name
      @name||=gensym("node")
      @name
    end
    # traverse from 1 node, collect all reachable nodes
    def collect(nodes=Set.new,transitions=Set.new,records=Set.new)
      @child_nodes ||= []
      @parent_nodes ||= []
      @sibling_nodes ||= []
      @record ||= nil
      nodes.add self
      if @record
        puts "set record"
        records.add @record
      end
      @child_nodes.each do |n|
        puts "collect child: #{n.dot_label}"
        transitions.add [self,n]
        n.collect(nodes,transitions,records) unless nodes.member? n
      end
      @parent_nodes.each do |n|
        puts "collect parent: #{n.dot_label}"
        transitions.add [n,self]
        n.collect(nodes,transitions,records) unless nodes.member? n
      end
      @sibling_nodes.each do |n|
        puts "collect sibling: #{n.dot_label}"
        n.collect(nodes,transitions,records) unless nodes.member? n
      end
      return nodes,transitions,records
    end

    # generate graph from this node on, reachability determined by self
    def dot_graph(io)
      io << <<END
digraph test_definition {
graph [ rankdir=LR ]
node [shape=record,fontname=helvetica]
END
      nodes,transitions,records = collect
      nodes.each do |n|
        next if n.record
        attrs={:label => '"'+n.dot_label+'"'}
        if n.respond_to? :dot_node_shape
          attrs[:shape]='"'+n.dot_node_shape+'"'
        end
        attr_string=attrs.map do |k,v|
          "#{k.to_s}=#{v}"
        end.join(", ")
        io.puts "#{n.node_name} [#{attr_string}]"
      end
      records.each do |rec|
        rec.dot_code(io)
      end
      transitions.each do |s,d|
        sname = s.node_name.to_s
        dname = d.node_name.to_s
        if s.record
          sname = s.record.node_name.to_s+':'+sname
        end
        if d.record
          dname = d.record.node_name.to_s+':'+dname
        end
        io.puts "#{sname} -> #{dname}"
      end
      io.puts "}"
    end
  end

  module DotRecord
    def props
      @port_nodes ||= []
      @name ||= DotNode.gensym("rec")
    end
    def add_port(*clist)
      props
      puts "port"
      clist.each do |c|
        unless @port_nodes.member? c
          @port_nodes.push c
          raise "node already in record" if c.record
          c.in_record self
        end
      end
    end
    def node_name
      props
      @name
    end
    # generate dot code for one record
    def dot_code(io)
      props
      portinfos = @port_nodes.map do |n|
        OpenStruct.new(name: n.node_name,
                       label: n.dot_label)
      end
      io << node_name << " [label=\"{"
      io << portinfos.map do |p|
        "<#{p.name}> #{p.label}"
        end.join(" | ")
      io << "}\"]\n"
    end
  end
end
