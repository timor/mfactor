require 'mfactor/image'
require 'mfactor/dot'
require 'mfactor/stack'
require 'parslet'


module MFactor

  # compilation:
  # for each definition:
  #  3. upgrade compatible types between the inferred stack effect and the user-provided one
  #  4. initialize virtual stacks (factor implementation calls them meta-d and meta-r for
  #  the data stack and the retain stack, respectiverly)
  #  for each word:
  #   1. if it is a primitive, record an operation into the stack (see below)
  #   2. if it is a shuffling word, execute it on the virtual stacks
  #   3. if it is another word, record a call operation into the stack (see below)
  #   4. if it is call, inline the quotation which MUST reside on the stack
  #  5. take the resulting operation graph, and generate a dot file
  #  6. generate a c file

  # Recording an operation involves taking the operands from the stack, and pushing one or
  # more items, which link the original input items on the stack with the corresponding
  # operation.  Also, the stack effect must be updated.  When doing so, the updated stack
  # effect must be checked against the given stack effect.  This can result in upgrading

  # Note on handling conditionals: when hitting if, both paths are virtually executed using
  # a copy of the currently active parameter and return stack.  After that, both stack
  # versions have to look the same, otherwise no compilation is possible, only execution.  A
  # phi node is inserted for every stack element that has been modified during the execution
  # of both possible paths.  To keep track of which stack elements need to be phi'd, the
  # stack is instructed to track the modifications since from the beginning of the if
  # execution part.  The stack containing the deepest modifications determines the number of
  # arguments that have to phi'd.

  def filename_escape(str)
    str.to_s.gsub(/[.><*=?:"]/,{
                    '.' => 'dot',
                    '>' => 'gt',
                    '<' => 'lt',
                    '*' => 'times',
                    '=' => 'equalp',
                    '?' => 'qm',
                    ':' => 'colon',
                    '"' => 'dquote'
                  })
  end
  module_function :filename_escape

  class CompileError < StandardError
  end

  class MFStaticCompiler
    attr_accessor :mf
    def initialize(mf)
      @mf=mf
      @compiled_definitions={}
      @current_def=nil
    end
    def infer_word(name)
      infer mf.find_name(name).body
    end
    def compile_definition(d)
      puts d.log("compiling definition: #{d.name}")
      @current_def = d
      graph=CDFG.new
      $stdout.flush
      inputs=d.effect.inputs.map{|i| MFInput.new(i.name,i.type)}
      saved_inputs=inputs.dup
      pstack = MFStack.new inputs
      rstack = MFStack.new
      if d.normal_word?
        compile_quotation(d.body,pstack,rstack,graph)
        outputs=pstack
        raise CompileError, "#{d.err_loc}: `#{name}` leaves quotations on stack, not supported yet" if
          outputs.items.any?{|i| i.is_a? Array}
        raise CompileError, "#{d.err_loc}: number of defined outputs (#{d.effect.outputs.length}) does not match with computed (#{outputs.length})" unless
          d.effect.outputs.length == outputs.length
        output_items=outputs.items.map.with_index do |x,i|
          o=Output.new(d.effect.outputs[i].name)
          graph.add_data_edge(x,o)
          o
        end
        d.log "final_p:"+pstack.show(true)
        d.log "final_r:"+rstack.show(true)
        input_record=MFStack.new(saved_inputs)
        graph.add_node input_record
        output_record=MFStack.new(output_items)
        graph.add_node output_record
        # dummy calls to compute ports, workaround so that ports are
        # sure to have their record fields set to avoid false duplicates when drawing
        output_record.get_port_nodes
        input_record.get_port_nodes
        d.graph = graph
        @compiled_definitions[d]=graph
        return graph
      else
        raise CompileError, "word not normal: #{d.name}"
      end
    end
    def compile_quotation(q,pstack,rstack,graph,control=nil)
      @current_def.log "compiling quotation: "+MFactor::see_word(q)
      q.each do |word|
        @current_def.log("p:"+pstack.show(true))
        @current_def.log("r:"+rstack.show(true))
        case word
        when MFWord then
          case word.name
          when "dup" then pstack._dup
          when "drop" then pstack.drop
          when "swap" then pstack.swap
          when ">r" then rstack.push pstack.pop
          when "r>" then pstack.push rstack.pop
          when "call" then
            @current_def.log "inlining literal quotation call"
            called_q=pstack.pop
            raise CompileError, "#{word.err_loc}:Error: call must be compiled with literal quotation on stack" unless called_q.is_a? Array
            control=compile_quotation(called_q,pstack,rstack,graph,control)
          when "if" then
            @current_def.log "compiling `if`"
            elsecode=pstack.pop
            thencode=pstack.pop
            condition=pstack.pop
            raise CompileError, "#{word.err_loc}:Error: if needs two literal quotations" unless
              (elsecode.is_a?(Array)) && (thencode.is_a?(Array))
            cnode=ChoiceNode.new("if")
            graph.add_control_edge(control,cnode)
            thenstack=pstack.dup.mark
            elsestack=pstack.mark
            res_then=compile_quotation(thencode,thenstack,rstack.dup,graph,cnode)
            res_else=compile_quotation(elsecode,elsestack,rstack,graph,cnode)
            #TODO: maybe insert crazy stack correctnes checking here
            raise CompileError, "#{word.err_loc}:Error: alternatives not stack effect compatible in `if`" unless
              thenstack.length == elsestack.length
            num_phis=[thenstack.get_marked,elsestack.get_marked].max
            phi=MFPhiNode.new(condition,[thenstack.items.last(num_phis),elsestack.items.last(num_phis)])
            num_phis.times do |i|
              graph.add_data_edge thenstack.items[-(num_phis-i)], phi.phi_inputs[i]
              graph.add_data_edge elsestack.items[-(num_phis-i)], phi.phi_inputs[i]
            end
            graph.add_data_edge condition,phi
            graph.add_control_edge res_then,phi
            graph.add_control_edge res_else,phi
            control=phi
            pstack.pop_n(thenstack.length)
            pstack.push_n phi.outputs
          else
            if word.definition.inline?
              @current_def.log "inlining `#{word.definition.name}` by definition"
              if word.definition.recursive?
                raise CompileError, "not yet compiling inline recursive combinators!"
              end
              control=compile_quotation(word.definition.body,pstack,rstack,graph,control)
            elsif pstack.items.last(word.definition.effect.inputs.length).any?{|i| i.is_a? Array }
              @current_def.log "auto-inlining `#{word.definition.name}` with quotation inputs"
              control=compile_quotation(word.definition.body,pstack,rstack,graph,control)
            else
              control=compile_word_call(word,pstack,graph,control)
            end
          end
        when MFIntLit then pstack.push word
        when MFByteLit then pstack.push word
        when Array then pstack.push word
        else raise CompileError, "unable to compile word of type: #{word.class}"
        end
      end
      control                      # return control
    end
    def compile_word_call(word,pstack,graph,control)
      # todo: type inference here!
      @current_def.log "compiling call to #{word.definition.name}"
      d=word.definition
      inputs=pstack.pop_n(d.effect.inputs.length)
      inputs ||= []
      @current_def.log "number of inputs: #{inputs.length}"
      call=MFCompiledCall.new(d)
      params=d.effect.inputs.map.with_index do |effectitem,i|
        @current_def.log "input #{i}"
        p=CallParameter.new(effectitem.name,i)
        graph.add_data_edge(inputs[i], p)
        call.add_port p
        p
      end
      call.add_port LabelNode.new(d.name),true
      @current_def.log "number of outputs: #{d.effect.outputs.length}"
      outputs=d.effect.outputs.map.with_index do |e,i|
        o=MFCallResult.new(call,i)
        call.add_port o
        o
      end
      call.inputs=params; call.outputs=outputs
      if control
        graph.add_control_edge control, call
      else
        graph.add_node call
      end
      pstack.push_n outputs
      @current_def.log "passing control to: #{call.node_name}"
      return call
    end
    def maybe_compile(d)
      compile_definition(d) unless @compiled_definitions[d]
    end
    def definition_dot_graph(d,io)
      maybe_compile(d)
      @compiled_definitions[d].dot(io) || raise(CompileError,"compilation of definition of #{d.name} unsuccessful")
    end
  end
end
