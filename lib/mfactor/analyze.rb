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

  # Note on handling conditionals: when hitting if, both paths are
  # virtually executed using a copy of the currently active parameter
  # and return stack.  After that, both stack versions have to look
  # the same, otherwise no compilation is possible, only execution.  A
  # phi node is inserted for every stack element that has been
  # modified during the execution of both possible paths.  To keep
  # track of which stack elements need to be phi'd, the stack is
  # compared at the end of the respective branches' virtual
  # interpretation.  The phi nodes are removed instantly when the
  # results are requested by successor nodes in the data flow graph.

  # Note on iteration constructs: Iteration is created whenever a tail
  # recursive combinator is inlined.  This is sufficient for all kinds
  # of loops.  There is one restriction regarding this: recursive
  # calls must always be the last thing in either a `then` or an
  # `else` branch.  When inlining the code for the combinator, the
  # current stacks are saved, and compared with the stack at the time
  # of the recursive invocation, which is the same as a backwards
  # jump.  All items that differ are basically loop variables.  Data
  # edges are inserted to indicate that data is effectively fed back
  # to where control was at the beginning of the loop.

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

  # signaled during Compilation error
  class CompileError < StandardError
  end

  # signaled when current Function is not compilable
  class UncompilableError < CompileError
  end

  class MFStaticCompiler
    attr_accessor :mf
    def initialize(mf)
      @mf=mf
      @compiled_definitions={}
      @current_def=nil
      @loop_labels=[]
      @loop_label_num='0'
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
      d.graph.inputs=inputs.dup
      pstack = MFStack.new inputs,d
      rstack = MFStack.new [],d
      if d.normal_word?
        d.graph.start=StartNode.new
        pstack,rstack,last_computation=compile_quotation(d.body,pstack,rstack,d.graph,d.graph.start)
        d.log "final_p:"+pstack.show(true)
        d.log "final_r:"+rstack.show(true)
        raise CompileError, "Retain Stack not empty" unless rstack.items.empty?
        outputs=pstack
        d.graph.end=EndNode.new
        d.graph.add_control_edge(last_computation,d.graph.end)
        raise UncompilableError, "`#{d.name}` leaves quotations on stack, not supported yet" if
          outputs.items.any?{|i| i.is_a? Array}
        raise CompileError, "Number of defined outputs (#{d.effect.outputs.length}) does not match with computed (#{outputs.length})" unless
          d.effect.outputs.length == outputs.length
        output_items=outputs.items.map.with_index do |x,i|
          o=Output.new(d.effect.outputs[i].name,d.effect.outputs[i].type)
          d.graph.add_data_edge(x,o)
          o
        end
        d.graph.outputs=output_items
        input_record=MFStack.new(d.graph.inputs,d)
        d.graph.add_node input_record unless d.graph.inputs.empty?
        output_record=MFStack.new(output_items,d)
        d.graph.add_node output_record unless output_items.empty?
        # dummy calls to compute ports, workaround so that ports are
        # sure to have their record fields set to avoid false duplicates when drawing
        output_record.get_port_nodes
        input_record.get_port_nodes
        @compiled_definitions[d]=d.graph # needed?
        d.compiled = true
        return d.graph                   # maybe better return definition?
      else
        raise UncompilableError, "word not normal: #{d.name}"
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
            raise UncompilableError, "Call must be compiled with literal quotation on stack. (Did you forget 'inline' declaration?)" unless called_q.is_a? Array
            pstack,rstack,control=compile_quotation(called_q,pstack,rstack,graph,control)
          when "if" then
            @current_def.log "compiling `if`"
            elsecode=pstack.pop
            thencode=pstack.pop
            condition=pstack.pop
            raise CompileError, "`if` needs two literal quotations" unless
              (elsecode.is_a?(Array)) && (thencode.is_a?(Array))
            cnode=ChoiceNode.new("if")
            graph.add_data_edge condition,cnode
            graph.add_control_edge(control,cnode) if control
            @current_def.log "compiling then branch"
            then_pstack,then_rstack,res_then,else_pstack,else_rstack,res_else = nil
            graph.in_branch :then do
              then_pstack,then_rstack,res_then=compile_quotation(thencode,pstack.dup,rstack.dup,graph,cnode)
            end
            @current_def.log "compiling else branch"
            graph.in_branch :else do
              else_pstack,else_rstack,res_else=compile_quotation(elsecode,pstack,rstack,graph,cnode)
            end
            @current_def.log "returning to if"
            @current_def.log "thenstack: "+then_pstack.show(true)
            @current_def.log "elsestack: "+else_pstack.show(true)
            #TODO: maybe insert crazy stack correctnes checking here
            if (then_pstack.items.last == :loop_case) || (else_pstack.items.last == :loop_case)
              @current_def.log "loop case found"
              if then_pstack.items.last == :loop_case # select correct stack to continue
                @current_def.log "discarding then_branch"
                cnode.jump = :then
                pstack=else_pstack
                rstack=else_rstack
                control=res_else
                graph.once_branch=:else
              else
                @current_def.log "discarding else_branch"
                cnode.jump = :else
                pstack=then_pstack
                rstack=then_rstack
                control=res_then
                graph.once_branch=:then
              end
            else
              raise CompileError, "Error: alternatives not stack compatible in `if`" unless
                (then_pstack.length == else_pstack.length) && (then_rstack.length == else_rstack.length)
              changed_indices=then_pstack.diff_index(else_pstack)
              @current_def.log("need to phi elements: #{changed_indices}")
              phi_nodes=changed_indices.map {|i| PhiNode.new([then_pstack.items[i],else_pstack.items[i]])}
              if_j=IfJoinNode.new("endif")
              graph.add_control_edge(res_then, if_j)
              graph.add_control_edge(res_else, if_j)
              control = if_j
              pstack.pop_n(then_pstack.length)
              pstack.push_n phi_nodes
            end
          else                  # word call
            if word.definition.inline?
              @current_def.log "inlining `#{word.definition.name}` by definition"
              if word.definition.recursive? # recursive inline word encountered
                # first check if this is a recursive call
                if (l=@loop_labels.detect {|x| x[:def_name] == @current_def.name})
                  @current_def.log "resolving inline recursive jump"
                  @current_def.log "pstack at time of entry:"+l[:entry_stack].show(true)
                  @current_def.log "pstack at time of jump:"+pstack.show(true)
                  @current_def.log "rstack at time of jump:"+rstack.show(true)
                  target=l[:join_node]
                  changed_inds=l[:entry_stack].diff_index(pstack)
                  @current_def.log "items to phi for backwards-jump: #{changed_inds}"
                  # insert the edges which constitute the dataflow into the backwards-jump
                  changed_inds.each do |i|
                    #graph.data_successors(l[:entry_stack].items[i]).each do |dest|
                    @current_def.log "adding backwards data edge"
                    graph.add_data_edge pstack.items[i], l[:entry_stack].items[i]
                    #end
                  end
                  @current_def.log "adding backwards control edge"
                  graph.add_control_edge control, target
                  pstack.push :loop_case
                  break;        # bails out of the remaining quotation compilation -> TODO: warn if continuation not empty (non-tail-recursive combinator)
                else            # recording call to inline recursive combinator
                  @current_def.log "compiling inline recursive combinator"
                  @current_def.log "pstack at entry: "+pstack.show(true)
                  @current_def.log "rstack at entry: "+rstack.show(true)
                  j=LoopJoinNode.new(@current_def.name+@loop_label_num.succ!)
                  @loop_labels.push({ :def_name => @current_def.name,
                                      :join_node => j,
                                      :entry_stack => pstack.dup})
                  graph.add_control_edge control, j if control
                  control=j
                  pstack,rstack,control=compile_quotation(word.definition.body,pstack,rstack,graph,control)
                  @loop_labels.pop
                end
              else
                pstack,rstack,control=compile_quotation(word.definition.body,pstack,rstack,graph,control)
              end
            elsif pstack.items.last(word.definition.effect.inputs.length).any?{|i| i.is_a? Array }
              @current_def.log "auto-inlining `#{word.definition.name}` with quotation inputs"
              pstack,rstack,control=compile_quotation(word.definition.body,pstack,rstack,graph,control)
            else
              control=compile_word_call(word,pstack,graph,control)
            end
          end
        when MFIntLit then pstack.push word
        when MFByteLit then pstack.push word
        when Array then pstack.push word
        when MFStringLit then pstack.push word
        else raise CompileError, "unable to compile word of type: #{word.class}"
        end
      end
      @current_def.log "return control from quotation"
      return pstack,rstack,control                      # return updated stacks and control
    end
    def compile_word_call(word,pstack,graph,control)
      # todo: type inference here!
      @current_def.log "compiling call to #{word.definition.name}"
      d=word.definition
      inputs=pstack.pop_n(d.effect.inputs.length) # actual parameters
      inputs ||= []
      @current_def.log "number of inputs: #{inputs.length}"
      params=d.effect.inputs.map.with_index do |effectitem,i|
        @current_def.log "input #{i}"
        p=CallParameter.new(effectitem.name,i)
        graph.add_data_edge(inputs[i], p)
        p
      end
      @current_def.log "number of outputs: #{d.effect.outputs.length}"
      outputs=d.effect.outputs.map.with_index do |e,i|
        MFCallResult.new(e, i)
      end
      call=MFCompiledCall.new(d,params,outputs)
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
