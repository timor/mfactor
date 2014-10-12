# data types that are used in compilation
require 'mfactor/dot.rb'

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
      "circle"
    end
    def dot_name_prefix
      "int"
    end
  end
  # special case: byte-sized literal
  class MFByteLit < MFIntLit
    def see
      "#B#{value}"
    end
  end

  class MFWord < Struct.new(:name,:definition,:is_tail)
    def initialize(*a)
      super *a
      @file=$current_mfactor_file
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
  class MFDefinition < Struct.new(:name,:definer,:effect,:body,:mods,:vocabulary,:file,:graph,:compile_log)
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
      (definer != "PRIM:") &&
        !(mods.member?("inline")) &&
        !(mods.member?("nocompile"))
    end
    def inline?
      mods.member? "inline"
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
  end

  class MFInput < Struct.new(:name,:type)
    include GraphNode
    def see
      self.name
    end
    def dot_label
      name
    end
    def dot_name_prefix
      "in"
    end
  end

  # represents a result of a compiled definition
  class Output < Struct.new(:name,:type)
    include GraphNode
    def dot_label
      name
    end
    def dot_name_prefix
      "out"
    end
  end
  
  class MFEffectItem < Struct.new(:name,:type)
  end
  
  class LabelNode < Struct.new(:label)
    include GraphNode
    def dot_label
      label
    end
    def dot_name_prefix
      "label"
    end
  end
  
  class ChoiceNode < Struct.new(:label)
    include GraphNode
    def dot_label
      label
    end
    def dot_node_shape
      "diamond"
    end
    def dot_name_prefix
      "choice"
    end
  end
  
  class CallParameter < Struct.new(:name,:index)
    include GraphNode
    def dot_label
      name
    end
  end
  # class CallOutput < Struct.new(:label)
  #   include GraphNode
  #   def dot_label
  #     label
  #   end
  # end

  class MFCompiledCall < Struct.new(:definition,:inputs,:outputs)
    include GraphNode
    include DotRecord
    def port_nodes
      inputs+[LabelNode.new(definition.name)]+outputs
    end
    def dot_name_prefix
      "call"
    end
  end

  class PhiInput < Struct.new(:name)
    include GraphNode
    def dot_label
      name
    end
  end
  # records concrete output of phi node
  # class PhiOutput < Struct.new(:label)
  #   include GraphNode
  #   def dot_label
  #     label
  #   end
  # end
  
  class PhiResult < Struct.new(:phi,:index)
    include GraphNode
    def dot_label
      "phi_#{index}"
    end
  end
  # Input_lists is a list (actually Array) of pointers to all inputs that have to be phi'd.
  # Input_lists usually are of the same length, one list corresponds to one alternative stack
  # image.
  class MFPhiNode
    include GraphNode
    include DotRecord
    attr_accessor :input_lists
    attr_reader :outputs
    attr_accessor :condition
    attr_reader :phi_inputs
    def initialize(condition,input_lists)
      @condition=condition
      @input_lists=input_lists
      @longest_input_list=input_lists.sort{|a,b| a.length <=> b.length}.last
      @phi_inputs=@longest_input_list.map.with_index do |input,i|
        phi_in=PhiInput.new("phi_i#{i}")
        add_port phi_in
        # @input_lists.each do |l|
        #   phi_in.add_parent l[i]
        # end
        phi_in
      end
      add_port LabelNode.new("phi"),true
      @outputs = @longest_input_list.map.with_index do |input,i|
        o=PhiResult.new(self,i)
        add_port o
        o
      end
    end
    # used as nodes for graphing
    def dot_name_prefix
      "phi_record"
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
  class MFCallResult < Struct.new(:call,:index)
    include GraphNode
    def name
      call.definition.effect.outputs[index][:name]
    end
    def type
      call.definition.effect.outputs[index][:type]
    end
    def see
      name
    end
    def dot_label
      name
    end
  end
end
