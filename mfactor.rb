# ruby version of the mfactor interpreter, which can be used to
# cross-compile an image to c, amongst other things

require 'parslet'
require 'yaml'

ISET=Hash[YAML.load_file("instructionset.yml").map{ |cname,name|
            [name==:private ? cname : (name || cname) , cname ] }]
puts ISET
if ISET["dup"]
  puts "yay"
end

class MFP < Parslet::Parser
  rule(:newline) { str("\n") >> str("\r").maybe }
  rule(:line_comment) { str('!') >> (newline.absent? >> any).repeat }
  rule(:space) { (line_comment | match('\s').repeat(1)).repeat }
  rule(:space?) { space.maybe }
  rule(:unsigned_dec) { match('[0-9]').repeat(1) }
  rule(:unsigned_hex) { str('0') >> match['xX'] >> match['0-9a-f'].repeat(1) }
  rule(:unsigned) { unsigned_hex | unsigned_dec }
  rule(:normal_word_char) { match['^\s:{\[\]};'] }
  rule(:normal_word) { str(')').absent? >> normal_word_char.repeat(1) }
  rule(:sequence_opener_word) { normal_word_char.repeat(1) >> str('{') }
  rule(:definer_word) { normal_word_char.repeat(0) >> str(':') }
  rule(:def_end) { str(';') }
  rule(:word) { sequence_opener_word | definer_word | normal_word }
  rule(:char) { str("'") >> match["^'"].as(:char) >> str("'") }
  rule(:atom) { char | unsigned.as(:unsigned) | normal_word.as(:word) }
  rule(:string) { str('"') >>
    ((str('\\')>>any)|(str('"').absent? >> any)).repeat(0).as(:string) >>
    str('"') }
  rule(:quotation_body) { ((quotation |
      string | literal_sequence | atom) >> space).repeat }
  rule(:literal_sequence) { sequence_opener_word.as(:seq_start) >> space >>
    quotation_body.as(:content) >> str('}') }
  rule(:quotation) { str('[') >> space >>
    quotation_body.as(:quotation_body) >> str(']') }
  rule(:stack_effect_element) { normal_word |
    ( definer_word >> space >> stack_effect ) }
  rule(:stack_effect) { str('(') >> space >>
    ( str('--').absent? >>  stack_effect_element >> space ).repeat >>
    str('--') >> space >>
    (str(')').absent? >> stack_effect_element >> space).repeat >> str(')')}
  rule(:definition) { definer_word.as(:def) >> space >>
    match('\S').repeat(1).as(:name) >> space >>
    (stack_effect.as(:effect) >> space).maybe >>
    quotation_body.as(:definition_body) >> def_end }
  rule(:program) { space? >> (definition >> space?).repeat }
  root(:program)
end

class MFWord < Struct.new(:name)
  def size
    5
  end
end
class MFPrim < MFWord
  def size
    1
  end
end
class MFIntLit < Struct.new(:value)
  def size
    5
  end
end
class MFByteLit < MFIntLit
  def size
    2
  end
end

class MFLitSequence
  def initialize(type,content)
    case type
    when "B{" then
      content.all? {|e| e.is_a?(MFByteLit) || raise( "not a byte literal: #{e}") } 
    when "I{" then
      content.all? {|e| e.is_a?(MFIntLit) || raise("not a byte literal: #{e}") } 
    else
      raise "unsupported literal sequence: '#{type} }"
    end
  end
  def size
    1 + content.map(:size).reduce(:+)
  end
end


# tree transformation to output a structure that represents one file
class MFTransform < Parslet::Transform
  rule(:unsigned => simple(:lit)) {
    num=(Integer(lit))
    (num > 255 ? MFIntLit : MFByteLit).new(num)
  }
  rule(:char => simple(:c)) { MFByteLit.new(c.to_s.ord) }
  rule(:string => simple(:s)) { s }
  rule(:word => simple(:name)) { (ISET[name.to_s] ? MFPrim : MFWord).new(name) }
  rule(:quotation_body => subtree(:b)) { b }
  # rule(:def => simple(:definer),
  #      :name => simple(:name),
  #      :effect => simple(:effect),
  #      :definition_body => sequence(:b)) {
  #   MFDefinition.new(definer,name,b)}
end

class MFDefinition < Struct.new(:name,:definer,:address,:effect,:body)
  def syntax_word?
    definer == "SYNTAX:"
  end
  def normal_word?
    definer == ":"
  end
  # determine word size in bytes
  def size
    def seqsize(seq)
      if seq == []
        0
      else
        elt = seq.shift
        s = if elt.is_a?(Array)
              2 + seqsize(elt)
            else
              elt.size
            end
        s + seqsize(seq)
      end
    end
    seqsize(body)
  end
end

# used to build up an application image composed of multiple source files
class MFactor
  @@parser = MFP.new
  @@transform = MFTransform.new
  def initialize
    @files={}
    @current_file=nil
    @defs={}              # holds the actual processed instances
                                # of the defined words
  end
  # call the parser on an input object (file)
  def parse(input)
    @@parser.parse(input)
  rescue Parslet::ParseFailed => failure
    cause=failure.cause
    def rec_print(cause)
      if cause.children != []
        cause.children.each do |c|
          rec_print(c)
        end
      end
      line,col=cause.source.line_and_column(cause.pos)
      puts "#{@current_file}:#{line}:#{col}: Error: #{cause.to_s}"
    end
    rec_print(cause)
    puts failure.cause.ascii_tree
    raise
  end
  # parse file, store into internal hash
  def load_file(file)
    @current_file=file
    puts "loading #{file}"
    STDOUT.flush
    result=@@transform.apply(parse(File.read(file)))
    @files[file] = result
    result
  end
  # check if word is known by name
  def known_word?(name)
    @defs[name]
  end
  # step through all the definitions of the files, checking
  # dependencies, building the index table
  def iterate_definitions
    counter = 0
    @files.each do |name,defs|
      puts "analyzing #{name}:"
      defs.each do |d|
        name = d[:name].to_s
        if existing=@defs[name]
          raise "word already exists: #{name}: #{existing[:body]}"
        else
          body = d[:definition_body]
          body.flatten.select{|e| e.is_a?(MFWord)}.each do |w|
            unless known_word? w
              raise "unknown word: #{w} in #{name}"
            end
          end
          word=MFDefinition.new(name,d[:definer],counter,d[:effect],body)
          @defs[name]=word
          counter += word.size
        end
      end
    end
    @defs
  end
end

# def mfparse(str)
#   p=MFP.new
#   t=MFTransform.new
#   t.apply(p.parse(str))
# rescue Parslet::ParseFailed => failure
#   puts failure.cause.ascii_tree
# end
