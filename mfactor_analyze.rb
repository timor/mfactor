require_relative 'mfactor'
require 'parslet'

class MFStack < Array
  def swap
    e1 = pop
    e2 = pop
    push e1
    push e2
  end
  def pop()
    if size == 0
      raise "stack empty!"
    else
      super
    end
  end
  def drop() pop end
  def dup()
    e = pop
    push e
    push e
  end
end

class MFStaticCompile
  attr_acccessor :mf
  def initialize(mf)
    @mf=mf
  end
  def walk
    mf.dictionary.values.each do |vocab|
      vocab.definitions.each do |d|
        pstack = MFStack.new
        rstack = MFStack.new
        if d.normal_word?
          d.body.each do |word|
            case word
            when MFPrim then
              case word.name
                when "dup" then 
                
  end
end
