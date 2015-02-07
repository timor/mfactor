# Generate Dot Code from ruby objects
# Include the Dot module,
# provide child_nodes() in nodes, optionally parent_nodes(), sibling_nodes()
# provide dot_label()
# optionally provide dot_record() which
# returns [record_object, position ]
module MFactor
  def c_escape(str)
    s=str.to_s.gsub(/^<(.+)>$/,'make_\1');
    s.gsub!(/(\w)(-)(\w)/){ $1+'_'+$3 };
    s.gsub!(/[-+.><*=,?@]/,{
              '+' => 'Plus',
              '-' => 'Minus',
              '.' => 'Show',
              '>' => 'Lt',
              '<' => 'Gt',
              '|' => 'Pipe',
              '*' => 'Times',
              '=' => 'Equal',
              ',' => 'Compile',
                '?' => 'Flag',
              '@' => 'At'
            })
    s
  end
  module_function :c_escape
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
    attr_accessor :record       # parent record, if this is a port node
    attr_accessor :control_out  # successor in control graph, convenience access
    attr_accessor :control_in_edge  # predecessor in control graph, only valid for non-join nodes (these have two)
    attr_accessor :symbol       # graph-local symbol name (for use as c variable, etc)
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
                       label: MFactor::dot_escape(n.dot_label)+(n.symbol ? "(#{n.symbol})":""))
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
    attr_writer :logger
    def initialize
      @nodes=[]
      @control_edges=[]         # an edge is an array [source,dest]
      @data_edges=[]            # an edge is an array [source,dest]
      @inputs=[]
      @outputs=[]
      @start,@end=nil
      @branch_stack = []             # :else or :then can be pushed when following an if choice
      @uid="0"                  # local variable suffix counter
      @logger=nil               # proc |msg| can be supplied for logging
    end
    # this needs only to be used when there is a node without a transition in the graph
    def add_node(n)
      @nodes.push n unless @nodes.include? n
    end
    def log (msg)
      if @logger
         @logger.call msg
      end
    end
    def backwards_annotate_last(node, tag, target)
      # move upwards through graph until target, tag the last edge that was follwed
      log "looking back at: #{node}"
      if node.control_in_edge[0] == target
        log "target found, tagging edge"
        node.control_in_edge[2] = tag
      else
        backwards_annotate_last(node.control_in_edge[0],tag,target)
      end
    end
    def add_control_edge(s,d)
      add_transition s,d
      label=nil
      s.control_out=d
      e = [s,d,label]
      log "adding non-unique control-in edge!" if d.is_a? IfJoinNode
      d.control_in_edge = e
      @control_edges.push e
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
      log "drawing graph "
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
        log "adding control edge: [#{s},#{d},#{label}]"
        attrs={color:"red",fontcolor:"red"}
        attrs[:label] = '"'+label+'"' if label
        draw_transition(s,d,io,attrs)
      end
      @data_edges.each do |s,d|
        log "adding data edge"
        draw_transition(s,d,io,{color: "green"})
      end
      io.puts "}"
      self
    end
    def control_out_edges node
      @control_edges.find_all{ |s,d| s == node}
    end
    # return all nodes that are followers of a given node (TODO: check performance)
    def data_successors node
      @data_edges.find_all{ |s,d| s == node }.map{ |s,d| d}
    end
    def data_predecessors node
      @data_edges.find_all{ |s,d| d == node }.map{ |s,d| s}
    end
    # iterate through nodes, mapping all connected nodes to the same symbol
    def assign_names
      @nodes.select{|n| n.is_a? MFInput}.each { |n| assign_arc_name n}
      @nodes.select{|n| n.is_a? Output}.each { |n| assign_arc_name n}
      @nodes.select{|n| n.is_a? MFCallResult}.each { |n| assign_arc_name n}
      # by now, all assigned literals (loop variables) should be named
      @nodes.select{|n| n.is_a? MFIntLit}.each { |n| assign_arc_name n}
      @nodes.select{|n| n.is_a? MFStringLit}.each { |n| assign_arc_name n} # TODO combine with other lits
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
    def assign_arc_name(node,symbol=nil)
      return if node.symbol
      # if this is a choice node, and no name has been computed, skip
      return if node.is_a? ChoiceNode and !symbol
      symbol ||=
        if node.is_a? MFIntLit
          node.value.to_s
        elsif node.is_a? MFStringLit
          '\"'+node.value+'\"'  # TODO escaping should be done when drawing!
        else
          MFactor::c_escape(node.name)+@uid.succ!
        end
      log "assigning '#{symbol}' to #{node.class}"
      node.symbol=symbol
      succs = data_successors(node)
      pres= data_predecessors(node)
      (pres+succs).each do |s|
        log "maybe assign same symbol name: #{s.class}"
        assign_arc_name s,symbol
      end
    end
  end
end
