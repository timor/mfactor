# Generate Dot Code from ruby objects
# Include the Dot module,
# provide child_nodes() in nodes, optionally parent_nodes(), sibling_nodes()
# provide dot_label()
# optionally provide dot_record() which
# returns [record_object, position ]
module MFactor
  def dot_escape(str)
    # str.to_s.gsub(/[-+.><*=]/,{
    str.to_s.gsub(/[><|]/,{
                    # '+' => 'plus',
                    #  '-' => 'minus',
                    #  '.' => 'dot',
                    '>' => '\>',
                    '<' => '\<',
                    '|' => '\|',
                    # '*' => 'times',
                    # '=' => 'equalp',
                  })
  end
  module_function :dot_escape
  def assert_is_node(n)
    raise "not a GraphNode: #{n}" unless n.is_a? GraphNode
  end
  module_function :assert_is_node
  module GraphNode
    require 'set'
    require 'ostruct'
    @@unique='1'
    attr_accessor :record
    attr_accessor :control_out
    # def add_child(*clist)
    #   puts "maybe add child to #{node_name}..."
    #   @child_nodes ||= []
    #   clist.each do |c|
    #     MFactor::assert_is_node(c)
    #     unless @child_nodes.member? c
    #       puts "yes"
    #       @child_nodes.push c
    #       c.add_parent self
    #     end
    #   end
    # end
    # def add_parent(*clist)
    #   puts "maybe add parent to #{node_name}..."
    #   @parent_nodes ||= []
    #   clist.each do |c|
    #     MFactor::assert_is_node(c)
    #     unless @parent_nodes.member? c
    #       puts "yes"
    #       @parent_nodes.push c
    #       c.add_child self
    #     end
    #   end
    # end
    # def add_sibling(*clist)
    #   puts "sibling to #{node_name}"
    #   @sibling_nodes ||= []
    #   clist.each do |c|
    #     MFactor::assert_is_node(c)
    #     unless @sibling_nodes.member? c
    #       @sibling_nodes.push c
    #       c.add_sibling self
    #     end
    #   end
    # end
    # overwrite equality test
    def ==(x)
      self.equal? x
    end
    def is_record?
      is_a? DotRecord
    end
    def gensym(s="G")
      (s.to_s+@@unique.succ!).to_sym
    end
    module_function :gensym
    def node_name
      @name||=gensym(self.class.to_s.split("::").last)
      # @name||=gensym("node")
      @name
    end
    # traverse from 1 node, collect all reachable nodes
    # def collect_nodes(nodes=[],transitions=Set.new)
    #   return nodes,transitions if nodes.member?(self)
    #   @child_nodes ||= []
    #   @parent_nodes ||= []
    #   @sibling_nodes ||= []
    #   self.record ||= nil
    #   nodes.push self
    #   puts "collected #{node_name}"
    #   if is_record?
    #     puts "collect port"
    #     get_port_nodes.map do |n|
    #       n.collect_nodes(nodes,transitions)
    #     end
    #   end
    #   if self.record
    #     puts "node in record"
    #     self.record.collect_nodes(nodes,transitions)
    #   end
    #   @child_nodes.each do |n|
    #     puts "collect child"
    #     transitions.add [self,n]
    #     n.collect_nodes(nodes,transitions)
    #   end
    #   @parent_nodes.each do |n|
    #     puts "collect parent"
    #     transitions.add [n,self]
    #     n.collect_nodes(nodes,transitions)
    #   end
    #   @sibling_nodes.each do |n|
    #     puts "collect sibling"
    #     n.collect_nodes(nodes,transitions)
    #   end
    #   return nodes,transitions
    # end

  end
  module DotRecord
    attr_accessor :handle_port
    def props
      @port_nodes ||= []
    end
    def add_port(c,handle_port_p=false)
      props
      if handle_port_p
        # puts "found handle"
        self.handle_port=c
      end
      # puts "port to #{node_name}"
      MFactor::assert_is_node(c)
      unless @port_nodes.member? c
        @port_nodes.push c
        raise "node already in record #{c.record.node_name}" if c.record
        c.record = self
      end
    end
    # if explicitely set, take that, otherwise rely on instance having implemented port_nodes
    def get_port_nodes
      props
      if @port_nodes.empty?
        # puts "ports lazy"
        pnodes = self.port_nodes() # TODO: not used, but should really compute everything instead of having to add ports manually!xb

        pnodes.each do |n|
          add_port n
        end
      end
      @port_nodes
    end
    def node_name
      @name||=gensym(self.class.to_s.split("::").last)
      @name
    end
    # generate dot code for one record
    def dot_code(io)
      # puts "drawing record"
      props
      portinfos = get_port_nodes.map do |n|
        OpenStruct.new(name: n.node_name,
                       label: MFactor::dot_escape(n.dot_label))
      end
      io << node_name << " [label=\"{{"
      io << portinfos.map do |p|
        "<#{p.name}> #{p.label}"
      end.join(" | ")
      io << "}}\"]\n"
    end
  end
  # control flow and data flow, enough information to generate some code (after de-SSA-ing)
  class CDFG
    attr_accessor :inputs
    attr_accessor :outputs
    attr_accessor :start
    attr_accessor :end
    attr_reader :nodes
    attr_writer :once_branch
    def initialize
      @nodes=[]
      @control_edges=[]         # an edge is an array [source,dest]
      @data_edges=[]            # an edge is an array [source,dest]
      @inputs=[]
      @outputs=[]
      @start,@end=nil
      @branch_stack = []             # :else or :then can be pushed when following an if choice
      @once_branch=nil               # can be set by loop case to make
                                     # control edge following the
                                     # recursive `if` work
    end
    # this needs only to be used when there is a node without a transition in the graph
    def add_node(n)
      @nodes.push n unless @nodes.include? n
    end
    def in_branch branch
      @branch_stack.push branch
      yield
      @branch_stack.pop
    end
    def add_control_edge(s,d)
      add_transition s,d
      label=nil
      # Check if we come from choice node.  If yes, label the correspondig edges
      if s.class == ChoiceNode
        # loop continuations live in else/ or then branches before
        # inlined, to keep depth correct, continuation case is handled
        # only once
        if @once_branch
          branch = @once_branch
          @once_branch = nil
        else
          branch = @branch_stack[-1]
        end
        raise "no branch specified following choice node" unless branch
        if branch == :else
          raise "node has more then one else edge" if s.else_edge
          s.else_edge = [s,d]
          label="else"
        elsif branch == :then
          raise "node has more then one then edge" if s.then_edge
          s.then_edge = [s,d]
          label="then"
        end
      end
      s.control_out=d
      @control_edges.push [s,d,label]
    end
    def add_data_edge(s,d)
      # Check if source is a PhiNode.  If so, add edges directly
      # between the inputs to the phi node and the destination.
      if s.is_a? PhiNode
        s.inputs.each do |i|
          add_data_edge i,d
        end
      else
        add_transition s,d
        @data_edges.push [s,d]
      end
    end
    # generate graph from this node on, reachability determined by self
    def dot(io)
      # puts "drawing"
      io << <<END
digraph test_definition {
graph [ rankdir=TB ]
node [shape=record,fontname=helvetica]
edge [fontname=helvetica, arrowsize=0.5]
END
      # nodes,transitions = collect_nodes
      #      transitions.to_a.flatten.to_set.each do |n|
      @nodes.each do |n|
        next if n.record        # if we are a port, skip, record handles drawing
        if n.is_record?          # if we are a record, call specialized function
          n.dot_code(io)
        else
          label_sym = (n.is_a?(JoinNode) ? :xlabel : :label)
          attrs={label_sym => '"'+n.dot_label+'"'}
          if n.respond_to? :dot_node_shape
            attrs[:shape]='"'+n.dot_node_shape+'"'
          end
          attr_string=attrs.map do |k,v|
            "#{k.to_s}=#{v}"
          end.join(", ")
          io.puts "#{n.node_name} [#{attr_string}]"
        end
      end
      @control_edges.each do |s,d,label|
        attrs={color:"red",fontcolor:"red"}
        attrs[:label] = '"'+label+'"' if label
        draw_transition(s,d,io,attrs)
      end
      @data_edges.each do |s,d|
        draw_transition(s,d,io,{color: "green"})
      end
      io.puts "}"
      self
    end
    
    # return all nodes that are followers of a given node (TODO: check performance)
    def data_successors node
      @data_edges.find_all{ |s,d| s == node }.map{ |s,d| d}
    end
    def data_predecessors node
      @data_edges.find_all{ |s,d| d == node }.map{ |s,d| s}
    end
    private
    def draw_transition(s,d,io,attrs={})
      sname = s.node_name.to_s
      dname = d.node_name.to_s
      if s.is_record? && s.handle_port
        # puts "using handle"
        sname = sname+':'+s.handle_port.node_name.to_s
      end
      if d.is_record? && d.handle_port
        # puts "using handle"
        dname = dname+':'+d.handle_port.node_name.to_s
      end
      if s.record
        sname = s.record.node_name.to_s+':'+sname
      end
      if d.record
        dname = d.record.node_name.to_s+':'+dname
      end
      attr_string = if attrs
                      ' ['+attrs.map {|k,v| "#{k.to_s}=#{v}"}.join(", ")+']'
                    else
                      ""
                    end
      io.puts "#{sname} -> #{dname}#{attr_string}"
    end
    # register nodes if necessary
    def add_transition(source,dest)
      add_node source
      add_node dest
      if source.record 
        add_node source.record
      end
      if dest.record 
        add_node dest.record
      end
    end
  end
end
