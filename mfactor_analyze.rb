require_relative 'mfactor'
require 'parslet'

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
  def push(a) @a.push a end
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
