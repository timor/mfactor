require_relative 'mfactor'
require 'parslet'

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

# gensyms
$unique='1'
def gensym(s="G")
  (s.to_s+$unique.succ!).to_sym
end

def combine_effects(effect1, effect2)
  in1,out1 = effect1.dup
  in2,out2 = effect2.dup
  if in2.length > out1.length
    raise "not enough items on stack #{out1} for input effect #{in2}"
  else
    [in1,out1[0..-in2.length-1]+out2]
  end
end

def infer(body)
  e=nil
  body.each do |w|
    next_effect=
      case w
      when String then [[],[w]]
      when MFIntLit then [[],[w.value]]
      when MFWord then  w.definition.effect
      when Array then [[],[infer(w)]]
      end
    if e
      e=combine_effects(e,next_effect)
    else
      e=next_effect
    end
    pp e
  end
  e
end

def get_stack_effect(d)
end

class MFStack
  def initialize(a=[])
    @a = a
  end
  def items
    @a
  end
  def swap
    e1 = @a.pop
    e2 = @a.pop
    @a.push e1
    @a.push e2
  end
  def pop()
    if @a.size == 0
      raise "stack empty!"
    else
      @a.pop
    end
  end
  def drop() @a.pop; nil end
  def dup()
    e = @a.pop
    @a.push e
    @a.push e
  end
  def push(x) @a.push x end
  # returns array
  def pop_n(n)
    if @a.length < n
      # TODO: raise something that can be caught and converted into meaningful stack checker error
      raise "not enough arguments on stack"
    else
      if n == 0
        []
      else
        @a,ret=@a[0..-(n+1)],@a[-n..-1]
        ret
      end
    end
  end
  def push_n(arr)
    @a+=arr
  end
  def show
    out=@a.map do |x|
      case x
      when MFInput then "#{x.name}(#{x.type})"
      when MFCallResult then "#{x.call.definition.name}[#{x.index}]"
      when MFIntLit then x.value.to_s
      when Array then "[...]"
      else
        raise "don't know how to print stack object of type #{x.class}"
      end
    end.join("|")
    puts out
  end
end

class MFInput < Struct.new(:name,:type)
  def see
    self.name
  end
end
class MFCompiledCall < Struct.new(:definition,:inputs,:outputs)
end
# That is a result of a call to another word, which points to the corresponding call.
# Index associates this result with the corresponding element in call's output stack
# effect sequence.
class MFCallResult < Struct.new(:call,:index)
  def name
    call.definition.effect[1][self.index][:name]
  end
  def type
    call.definition.effect[1][self.index][:type]
  end
  def see
    name
  end
end

def escape(str)
  str.to_s.gsub(/[-+.><]/,{
             '+' => 'plus',
             '-' => 'minus',
             '.' => 'dot',
             '>' => 'gt',
             '<' => 'lt'})
end

# input: {port =>input,...}
def dot_record(id,name,inputs,outputs,io,nodes)
  puts "generating dot record for #{id}: #{name}"
  inputs.values.map do |i|
    dot_code(i,io,nodes) unless nodes[i]
  end
  edges=[]
  io << "#{id} [label=\"#{name} | "
  io << inputs.map do |port,input|
    port_id=gensym(port)
    edges << "#{nodes[input]} -> #{id}:#{port_id}"
    "<#{port_id}> #{port}"
  end.join(" | ")
  if outputs
    io << " | -- | "
    io << outputs.map do |o|
      port=gensym(o.type)
      nodes[o]= "#{id}:#{port}"
      "<#{port}> #{o.see}"
    end.join(" | ")
  end
  io.puts "\"]"
  edges.each{|e| io.puts(e)}
  return edges
end

def dot_code(thing, io,nodes={})
  case thing
  when MFInput then 
    id=gensym(thing.name)
    nodes[thing]=id
    io.puts "#{id} [label=\"#{thing.name}\"]"
  when MFCompiledCall then
    id=gensym(escape(thing.definition.name))
    ins=Hash[thing.definition.effect[0].map{|x| x.name}.zip(thing.inputs)]
    dot_record(id,thing.definition.name,ins,thing.outputs,io,nodes)
  when MFStack then           # output stack, behaves like inputs
    id = gensym("stack")
    elts=Hash[(1..thing.items.length).map{|i| id.to_s+i.to_s}.zip(thing.items)]
    dot_record(id,"stack",elts,nil,io,nodes)
  when MFCallResult then
    dot_code(thing.call,io,nodes)
  when MFIntLit then
    nodes[thing]=thing.value.to_s
  else raise "cannot generate dot code for #{thing}"
  end
end

class MFStaticCompiler
  attr_accessor :mf
  def initialize(mf)
    @mf=mf
    @compiled_definitions={}
  end
  def infer_word(name)
    infer mf.find_name(name).body
  end
  def compile_definition(name)
    puts "compiling definition: #{name}"
    d=mf.find_name(name)
    inputs=d.effect[0].map{|i| MFInput.new(i[:name],i[:type])}
    pstack = MFStack.new inputs
    rstack = MFStack.new
    if d.normal_word?
      outputs=compile_quotation(d.body,pstack,rstack)
      @compiled_definitions[name]=MFCompiledCall.new(d,inputs,outputs)
    else
      raise "word not normal: #{d.name}"
    end
  end
  def compile_quotation(q,pstack,rstack)
    print "compiling quotation: "; puts see_word(q)
    q.each do |word|
      print "p:"; pstack.show
      print "r:"; rstack.show
      case word
      when MFWord then
        case word.name
        when "dup" then pstack.dup
        when "drop" then pstack.drop
        when "swap" then pstack.swap
        when ">r" then rstack.push pstack.pop
        when "r>" then pstack.push rstack.pop
        when "call" then
          puts "inlining literal quotation call"
          called_q=pstack.pop
          raise "#{word.err_loc}:Error: call must be compiled with literal quotation on stack" unless called_q.is_a? Array
          compile_quotation(called_q,pstack,rstack)
        else
          if word.definition.inline?
            puts "inlining #{word.definition.name}"
            compile_quotation(word.definition.body,pstack,rstack)
          else
            compile_word_call(word,pstack)
          end
        end
      when MFIntLit then pstack.push word
      when MFByteLit then pstack.push word
      when Array then pstack.push word
      else raise "unable to compile word of type: #{word.class}"
      end
    end
    pstack                      # return the last state
  end
  def compile_word_call(word,pstack)
    # todo: type inference here!
    puts "compiling call to #{word.definition.name}"
    d=word.definition
    inputs=pstack.pop_n(d.effect[0].length)
    call=MFCompiledCall.new(d)
    i=-1
    outputs=d.effect[1].map do |e|
      i+=1
      MFCallResult.new(call,i)
    end
    call.inputs=inputs; call.outputs=outputs
    pstack.push_n outputs
  end
  def maybe_compile(name)
    compile_definition(name) unless @compiled_definitions[name]
  end
  def word_dot_graph(name,io)
    maybe_compile(name)
    io << <<END
digraph #{name}_definition {
node [shape=record,fontname=helvetica]
END
    dot_code(@compiled_definitions[name].outputs,io)
    io.puts "}"
  end
end
