# data types that are used in compilation
require 'mfactor/graph.rb'

module MFactor
  # integer literal
  class MFIntLit < Struct.new(:value)
    include GraphNode
    def see
      "#I#{value}"
    end
    def dot_label
      value.to_s
    end
    def dot_node_shape
      "none"
    end
  end
  # special case: byte-sized literal
  class MFByteLit < MFIntLit
    def see
      "#B#{value}"
    end
  end

  class MFStringLit < Struct.new(:value)
    include GraphNode
    def see
      value.inspect
    end
    def dot_label
      '\"'+value+'\"'
    end
    def dot_node_shape
      "none"
    end
  end
  class MFWord < Struct.new(:name,:definition,:is_tail)
    def initialize(*a)
      super *a
      @file=$current_mfactor_file
    end
    def inspect
      "#<Word:#{definition.vocab}:#{name}>"
    end
    def see
      name.to_s.downcase
    end
    def err_loc
      line,col=name.line_and_column
      "#{@file}:#{line}:#{col}"
    end
    def change_name(newname)
      old=name
      name=Parslet::Slice.new(old.position,newname,old.line_cache)
    end
  end

  # Definition object, which can be moved into dictionary
  # file: source file of the definition
  # graph: if set, points to the graph resulted by partial evaluation.  basis for code generation and petri-net simulation
  class MFDefinition < Struct.new(:name,:definer,:effect,:body,:mods,:vocabulary,:file,:graph,:compile_log,:compiled)
    def initialize(*args)
      super(*args)
      convert_tailcalls(body)
    end
    def syntax_word?
      definer == "SYNTAX:"
    end
    def normal_word?
      definer == ":"
    end
    def primitive?
      definer == "PRIM:"
    end
    def compilable?
      (definer == ":") &&
        # !(mods.member?("inline")) &&
        !(mods.member?("nocompile"))
    end
    def inline?
      mods.member? "inline"
    end
    def inline_body             # return a duplicate of body for inlining
      dup_array body
    end
    def recursive?
      mods.member? "recursive"
    end
    # return printed location of definition
    def err_loc
      line,col=definer.line_and_column
      "#{file}:#{line}:#{col}"
    end
    def see
      ": #{name} #{effect} "+
        body.map{ |elt| see_word(elt) }.join(" ")
    end
    def inspect
      "#<MFDefinition:#{name}"
    end
    # TODO: move out of here, into emitter
    def convert_tailcalls(b)
      if b[-1].is_a? MFWord
        b[-1].is_tail = true
        # puts "#{b[-1].err_loc}:Info: tailcall"
      end
      b.each do |elt|
        if elt.is_a?(Array)
          convert_tailcalls(elt)
        end
      end
    end
    # attach something to the compilation log
    def log (s)
      self.compile_log ||= ""
      self.compile_log += s
      self.compile_log += "\n"
      s
    end
    private
    def dup_array(a)
      a.map do |elt|
        if elt.is_a? Array
          dup_array elt
        else
          elt.dup
        end
      end
    end
  end

  class MFInput < Struct.new(:name,:type)
    include GraphNode
    def see
      self.name
    end
    def dot_label
      name
    end
  end

  # represents a result of a compiled definition
  class Output < Struct.new(:name,:type)
    include GraphNode
    def dot_label
      name
    end
  end

  class MFEffectItem < Struct.new(:name,:type)
  end

  class LabelNode < Struct.new(:dot_label)
    include GraphNode
  end

  class EndNode
    include GraphNode
    def dot_node_shape
      "Mrecord"
    end
    def dot_label
      "End"
    end
  end

  class StartNode
    include GraphNode
    def dot_node_shape
      "Mrecord"
    end
    def dot_label
      "Start"
    end
  end

  class JoinNode < Struct.new(:dot_label)
    include GraphNode
    def dot_node_shape
      "point"
    end
  end

  class NopNode
    include GraphNode
    def dot_node_shape
      "point"
    end
    def dot_label
      ""
    end
  end

  class IfJoinNode < JoinNode
  end

  class LoopJoinNode < JoinNode
    def dot_label
    "repeat"
    end
  end

  # jump is either nil,:then or :else
  class ChoiceNode < Struct.new(:label,:then_edge,:else_edge,:jump)
    include GraphNode
    def dot_label
      label
    end
    def dot_node_shape
      "diamond"
    end
  end

  class CallParameter < Struct.new(:name,:index)
    include GraphNode
    def dot_label
      name
    end
  end

  class MFCompiledCall
    include GraphNode
    include DotRecord
    attr_reader :definition
    attr_reader :inputs
    attr_reader :outputs
    def initialize(definition, inputs, outputs)
      @definition=definition
      @inputs=inputs
      @outputs=outputs
      inputs.each do |i|
        add_port i
      end
      add_port LabelNode.new(definition.name)
      outputs.each do |o|
        add_port o
      end
    end
  end

  class PhiNode < Struct.new(:inputs)
    include GraphNode
    def dot_label
       raise "Phi node not substituted by data edges!"
    end
  end

  # input nodes of compiled call
  class CallInput < Struct.new(:label)
    include GraphNode
    def dot_label
      label
    end
  end

  # inputs and outputs are supposed to be lists of MFEffectItems
  class StackEffect < Struct.new(:inputs,:outputs)
  end

  # That is a result of a call to another word, which points to the corresponding call.
  # Index associates this result with the corresponding element in call's output stack
  # effect sequence.
  class MFCallResult < Struct.new(:output_effect, :index)
    include GraphNode
    def name
      output_effect[:name]
    end
    def type
      output_effect[:type]
    end
    def see
      name
    end
    def dot_label
      name
    end
  end
end
