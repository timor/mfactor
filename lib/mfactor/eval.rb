module MFactor
  class Eval
    def >>(n)
      advance n
    end
    def initialize(a=[])
      @a=a
      self
    end
    def dup
      @a+=[@a[-1]]
      self
    end
    def drop
      @a=@a[0...-1]
      self
    end
    def clear
      @a=[]
      self
    end
    def S(s)
      @a.push s
      self
    end
    def print
      super @a.pop
      self
    end
    def push elt
      @a.push elt
      self
    end
    def method_missing(name)
      if name[0] == 'I'
        @a.push name[1..-1].to_i
        self
      elsif @a[-1].respond_to? name
        @a.push @a.pop.send(name)
        self
      else
        raise "unknown word: '#{name}'"
      end
    end
    def q &proc
      @a.push proc
      self
    end
    def call
      self.instance_eval &@a.pop
      self
    end
    def _?
      if @a.pop
        @a.pop
      else
        @a.delete_at -2
      end
      self
    end
    def [](*args)
      args.each do |n|
        advance n
      end
      self
    end
    def define (name, arr)
      define_singleton_method(name) do
        self[*arr]
      end
      self
    end
    private
    def advance n
      if n.is_a? Symbol
        send n
      else 
        @a.push n
      end
      self
    end
  end

end
