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
end

class MFStaticCompiler
  attr_accessor :mf
  def initialize(mf)
    @mf=mf
  end
  def infer_word(name)
    infer mf.find_name(name).body
  end
  def compile_word(name)
    d=mf.find_name name
    pstack = MFStack.new(d.effect[0])
    rstack = MFStack.new
    if d.normal_word?
      d.body.each do |word|
        pp pstack
        case word
        when MFPrim then
          case word.name
          when "dup" then pstack.dup
          when "drop" then pstack.drop
          when "swap" then pstack.swap
          when ">r" then rstack.push pstack.pop
          when "r>" then pstack.push rstack.pop
          else raise "don't know how to interpret #{word.name}"
          end
        when MFIntLit then word
        when MFByteLit then word
        when MFWord then word
        end
      end
    else
      raise "word not normal: #{d.name}"
    end
  end
end
