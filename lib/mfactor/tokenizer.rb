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
      return enum_for(:each) unless block_given?
      col=0
      lnum=0
      while line=@s.gets
        lnum=lnum+1
        col=0
        line=StringIO.new(line.chomp)
        while part=line.gets(" ")
          token=part.chomp(" ").gsub(/\t/,"")
          yield Token.new(token, lnum, col) if token != ""
          col = col + part.length
        end
      end
    end
  end
end
