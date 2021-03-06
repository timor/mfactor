require 'mfactor/vocab'
# for the definition object
require 'mfactor/datatypes'
require 'mfactor/tokenizer'
require 'stringio'

module MFactor
  class Eval
    attr_accessor :primitives  # for debugging
    def initialize(a=[],input=nil)
      @variables=[]             # array for holding special variables
      @dictionary={}            # the dictionary: "name"->Vocab pairs
      bootvocab=Vocabulary.new("bootvocab")
      @search_vocabs=[bootvocab]
      @current_vocab=bootvocab
      # if the current vocab is bootstrap, all definitions go into this object itself
      @a=a
      @r=[]
      @primitives={
        :not => proc { @a[-1] = !@a[-1] },
        :> => proc { @a[-1]=(@a.pop < @a[-1]) },
        :equalp => proc { @a[-1]=(@a.pop == @a[-1]) },
        :dup => proc { @a+=[@a[-1]] },
        :over => proc { @a.push @a[-2] },
        :drop => proc { @a=@a[0...-1] },
        :clear => proc { @a=[] },
        :print => proc { print @a.pop },
        :swap => proc { @a[-2],@a[-1] = @a[-1],@a[-2] },
        :to_r => proc { @r.push @a.pop },
        :r_from => proc { @a.push @r.pop },
        :_? => proc { if @a.delete_at(-3); @a.pop else @a.delete_at -2 end },
        :call => proc { case callable = @a.pop
                        when Array then callable.each {|w| eval w }
                        when Proc then instance_eval &callable
                        else raise "cannot call #{callable}"
                        end },
        :token => proc { @a.push begin
                                   @tokenizer.next
                                 rescue StopIteration
                                   nil
                                 end },
        :compose => proc { compose },
        :curry => proc { curry }
      }
      if input
        open input
      end
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
    def pop
      @a.pop
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
    def rstack
      @r
    end
    # set @tokenizer to an enumerator that responds to :next
    def open thing
      @tokenizer =
        case thing
        when String then Tokenizer.new(StringIO.new(thing)).each
        else Tokenizer.new(thing).each
        end
      self
    end
    def eval n
      case n
      when Symbol then
        # first check current vocab for definition
        unless (d=search n.to_s).nil?
          self.[] *d.code      # execute body
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
      define :if, [ :_?, :call ]
      define :dip, [ :swap, :to_r, :call, :r_from ]
      define :twodip, [ :swap, [ :dip ], :dip ]
      define :twodup, [ :over, :over ]
      define :keep, [ :over, [ :call ], :dip ]
      define :when, [ :swap, [ :call ], [ :drop ], :if ]
      define :loop, [ [ :call ], :keep, [ :loop ], :curry, :when ]
      define :do, [ :dup, :twodip ]
      define :while, [ :swap, :do, :compose, [ :loop ], :curry, :when ]
      define :<=, [ :>, :not ]
      define :dupd, [ :to_r, :dup, :r_from ]
      define :or, [ :dupd, :_? ]
      define :>=, [ :twodup, :>, [ :equalp ], :dip, :or ]
      define :<, [ :>=, :not ]
      define :neg, [ proc { push(- pop())}, :call ]
      define :minus, [ :neg, :+ ]
      define :suffix!, [ proc { @a[-2] << @a.pop }, :call]
      define :scan_datum, [ :token, proc { push Kernel.eval(pop) }, :call ]
    end
    private
    def compose
      proc_2=@a.pop
      proc_1=@a.pop
      push [ proc_1, :call, proc_2, :call ]
    end
    def curry
      @a[-2]=[ @a[-2] ]
      compose
    end
  end
end
