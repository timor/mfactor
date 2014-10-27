require 'mfactor/graph'
require 'mfactor/datatypes'

module MFactor

  # stack for virtual interpretation
  class MFStack
    include GraphNode
    include DotRecord
    attr_accessor :marks
    def initialize(a=[],definition=nil)
      @a = a
      @definition = definition
    end
    def initialize_copy(source)
      super
      @a = source.items.dup
    end
    def items
      @a
    end
    def each
      @a.each
    end
    def swap
      e1 = pop
      e2 = pop
      @a.push e1
      @a.push e2
    end
    def pop()
      if @a.size == 0
        raise "stack empty!"
      else
        ret = @a.pop
      end
      ret
    end
    def drop() self.pop; nil end
    def _dup()
      e = pop
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
        end
        ret
      end
    end
    def push_n(arr)
      @a+=arr
    end
    def length
      @a.length
    end
    def show(arg=false)
      out=@a.map do |x|
        case x
        when MFInput then "#{x.name}(#{x.type})"
        when MFCallResult then "res[#{x.index}]"
        when PhiResult then "phi[#{x.index}]"
        when MFIntLit then x.value.to_s
        when Array then "[...]"
        when Symbol then x.inspect
        when MFStringLit then x.value.inspect
        else
          raise "don't know how to print stack object of type #{x.class}"
        end
      end.join("|")
      if arg
        out
      else
        puts out
      end
    end
    def port_nodes
      items
    end
    def diff_index(other)
      raise "trying to diff inconsistent stack lengths" unless
        other.length == items.length
      items.each_index.select { |i| items[i] != other.items[i] }
    end
    private
    def log s
      if @definition
        @definition.log s
      end
    end
  end
end
