require 'mfactor/vocab'
# for the definition object
require 'mfactor/parser'

module MFactor
  class Token < String
    attr_reader :line, :column
    def initialize(str, line, col)
      super str
      @line=line
      @column=col
    end
  end
  class Tokenizer
    include Enumerable
    attr_reader :filename
    def initialize source
      @filename = (source.is_a? File and source.path)
      @s=source
    end
    def each
      col=0
      lnum=0
      while line=@s.gets
        line.chomp
        lnum=lnum+1
        col=0
        line=StringIO.new(line)
        while part=line.gets(" ")
          token=part.chomp(" ").gsub(/\t/,"")
          yield Token.new(token, lnum, col) if token != ""
          col = col + part.length
        end
      end
    end
  end
  class Eval
    attr_accessor :primitives  # for debugging
    def initialize(a=[])
      @variables=[]             # array for holding special variables
      @dictionary={}            # the dictionary: "name"->Vocab pairs
      bootvocab=Vocabulary.new("bootvocab")
      @search_vocabs=[bootvocab]
      @current_vocab=bootvocab
      # if the current vocab is bootstrap, all definitions go into this object itself
      @a=a
      @primitives={
        :dup => proc { @a+=[@a[-1]] },
        :drop => proc { @a=@a[0...-1] },
        :clear => proc { @a=[] },
        :print => proc { print @a.pop },
        :swap => proc { @a[-2],@a[-1] = @a[-1],@a[-2] },
        :_? => proc { if @a.pop ; @a.pop else @a.delete_at -2 end },
        :call => proc { @a.pop.each {|w| eval w } }
      }
      self
    end
    def >>(n)
      eval n
    end
    def clear
      @a=[]
      self
    end
    def S(s)
      @a.push s
      self
    end
    def push elt
      @a.push elt
      self
    end
    def [](*args)
      args.each do |n|
        eval n
      end
      self
    end
    def define (namesym, arr)
      @current_vocab.add MFDefinition.new(namesym.to_s,":",nil,arr,[])
      self
    end
    def pstack
      @a
    end
    def eval n
      case n
      when Symbol then
        # first check current vocab for definition
        unless (d=search n.to_s).nil?
          self.[] *d.body      # execute body
        else
          if @primitives[n]
            @primitives[n].call
          elsif @a[-1].respond_to? n  # allow calling ruby methods of TOS
            target = @a.pop
            nargs = target.method(n).arity
            nargs = -nargs-1 if nargs < 0
            if nargs > 0
              @a,args = @a[0...-nargs],@a[-nargs..-1]
            else
              args = []
            end
              @a.push target.send(n,*args)
          else
            raise "unknown word: '#{n}'"
          end
        end
      when Proc then
        self.instance_eval &n
      else 
        @a.push n
      end
      self
    end
    # search for name
    def search name
      @search_vocabs.each do |vocab|
        unless (d=vocab.find(name)).nil?
          return d
        end
      end
      nil
    end
    # when called, boot up an evaluator that is actually able to parse more definitions
    def boot
    end
  end
end
