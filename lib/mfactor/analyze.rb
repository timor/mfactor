require 'mfactor/image'
require 'mfactor/graph'
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
      @loop_labels=[]
    end
    def infer_word(name)
      infer mf.find_name(name).body
    end
    def compile_definition(d)
      puts d.log("compiling definition: #{d.name}")
      @current_def = d
      d.graph=CDFG.new
      $stdout.flush
      inputs=d.effect.inputs.map{|i| MFInput.new(i.name,i.type)}
      saved_inputs=inputs.dup
      pstack = MFStack.new inputs,d
      rstack = MFStack.new [],d
      if d.normal_word?
        start=StartNode.new
        last_computation=compile_quotation(d.body,pstack,rstack,d.graph,start)
        outputs=pstack
        d.graph.add_control_edge(last_computation,EndNode.new)
        d.log "final_p:"+pstack.show(true)
        d.log "final_r:"+rstack.show(true)
        raise CompileError, "#{d.err_loc}: `#{d.name}` leaves quotations on stack, not supported yet" if
          outputs.items.any?{|i| i.is_a? Array}
        raise CompileError, "#{d.err_loc}: number of defined outputs (#{d.effect.outputs.length}) does not match with computed (#{outputs.length})" unless
          d.effect.outputs.length == outputs.length
        output_items=outputs.items.map.with_index do |x,i|
          o=Output.new(d.effect.outputs[i].name)
          d.graph.add_data_edge(x,o)
          o
        end
        input_record=MFStack.new(saved_inputs,d)
        d.graph.add_node input_record unless saved_inputs.empty?
        output_record=MFStack.new(output_items,d)
        d.graph.add_node output_record unless output_items.empty?
        # dummy calls to compute ports, workaround so that ports are
        # sure to have their record fields set to avoid false duplicates when drawing
        output_record.get_port_nodes
        input_record.get_port_nodes
        @compiled_definitions[d]=d.graph # needed?
        return d.graph                   # maybe better return definition?
      else
        raise CompileError, "word not normal: #{d.name}"
      end
    end
    def compile_quotation(q,pstack,rstack,graph,control)
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
            raise CompileError, "#{word.err_loc}:Error: `if` needs two literal quotations" unless
              (elsecode.is_a?(Array)) && (thencode.is_a?(Array))
            cnode=ChoiceNode.new("if")
            graph.add_data_edge condition,cnode
            graph.add_control_edge(control,cnode) if control
            thenstack=pstack.dup
            elsestack=pstack
            @current_def.log "compiling then branch"
            res_then=compile_quotation(thencode,thenstack,rstack.dup,graph,cnode)
            @current_def.log "compiling else branch"
            res_else=compile_quotation(elsecode,elsestack,rstack,graph,cnode)
            @current_def.log "returning to if"
            @current_def.log "thenstack: "+thenstack.show(true)
            @current_def.log "elsestack: "+elsestack.show(true)
            #TODO: maybe insert crazy stack correctnes checking here
            if (thenstack.items.last == :loop_case) || (elsestack.items.last == :loop_case)
              @current_def.log "loop case found"
              if thenstack.items.last == :loop_case # select correct stack to continue
                pstack=elsestack
                control=res_else
              else
                pstack=thenstack
                control=res_then
              end
            else
              raise CompileError, "#{word.err_loc}:Error: alternatives not stack effect compatible in `if`" unless
                thenstack.length == elsestack.length
              phi_indices=thenstack.diff_index(elsestack)
              @current_def.log("need to phi elements: #{phi_indices}")
              phi=MFPhiNode.new(condition,[thenstack.items.values_at(*phi_indices),elsestack.items.values_at(*phi_indices)])
              phi_indices.each_with_index do |i,phi_i|
                graph.add_data_edge thenstack.items[i], phi.phi_inputs[phi_i]
                graph.add_data_edge elsestack.items[i], phi.phi_inputs[phi_i]
              end
              if_j=JoinNode.new("if")
              graph.add_control_edge(res_then, if_j)
              graph.add_control_edge(res_else, if_j)
              control = if_j
              pstack.pop_n(thenstack.length)
              pstack.push_n phi.outputs
            end
          else                  # word call
            if word.definition.inline?
              @current_def.log "inlining `#{word.definition.name}` by definition"
              if word.definition.recursive? # recursive inline word encountered
                # first check if this is a recursive call
                if (l=@loop_labels.detect {|x| x[:def_name] == @current_def.name})
                  @current_def.log "resolving inline recursive jump"
                  @current_def.log "pstack at time of jump:"+pstack.show(true)
                  target=l[:join_node]
                  changed_inds=l[:entry_stack].diff_index(pstack)
                  @current_def.log "items to phi for backwards-jump: #{changed_inds}"
                  # insert the edges which constitute the dataflow into the backwards-jump
                  changed_inds.each do |i|
                    graph.data_successors(l[:entry_stack].items[i]).each do |dest|
                      @current_def.log "adding backwards data edge"
                      graph.add_data_edge pstack.items[i], dest
                    end
                  end
                  graph.add_control_edge control, target
                  pstack.push :loop_case
                  break;        # bails out of the remaining quotation compilation -> TODO: warn if continuation not empty (non-tail-recursive combinator)
                else            # recording call to inline recursive combinator
                  @current_def.log "compiling inline recursive combinator"
                  j=JoinNode.new(@current_def.name)
                  @loop_labels.push({ :def_name => @current_def.name,
                                      :join_node => j,
                                      :entry_stack => pstack.dup})
                  graph.add_control_edge control, j if control
                  control=j
                  control=compile_quotation(word.definition.body,pstack,rstack,graph,control)
                  @loop_labels.pop
                end
              else
                control=compile_quotation(word.definition.body,pstack,rstack,graph,control)
              end
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
      begin
        maybe_compile(d)
      rescue Exception
        raise
      ensure
        if d.graph
          d.graph.dot(io)
        end
      end
    end
  end
end
