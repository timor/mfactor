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
      @marks=[]
      @definition = definition
    end
    def initialize_copy(source)
      super
      @a = source.items.dup
      @marks= source.marks.dup
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
      update_marks
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
        update_marks
        ret
      end
    end
    def push_n(arr)
      @a+=arr
    end
    def mark
      log "marking"
      m=Mark.new(@a.length,self)
      @marks.push(m)
      m
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
    private
    def update_marks
      #log "updating #{@marks.length} marks"
      @marks.each do |m|
        if (m.pos > @a.length)
          log "setting mark to #{@a.length}"
          m.pos = @a.length
        end
        m
      end
    end
    def log s
      if @definition
        @definition.log s
      end
    end
  end
  class Mark < Struct.new :pos, :stack
    # return number of items that has been changed since most recent
    # call of mark, deregistering the mark
    def get
      l=stack.items.length - pos
      stack.send :log, "pop mark, stack has #{stack.items.length} items, marked #{l}"
      stack.marks.delete(self) or raise "unable to delete mark, not found in stack"
      l
    end
  end
end
