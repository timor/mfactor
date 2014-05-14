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

# parser class, will parse one source file when parse() method is
# called
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
  rule(:in_declaration) { str('IN:') >> space >> normal_word.as(:current_dict) }
  rule(:use_declaration) { str('USING:') >> space >>
    (normal_word.as(:used_dict_name) >> space).repeat >> space >> str(';') }
  rule(:dict_header) { use_declaration.as(:use_decl) >> space >> in_declaration }
  rule(:program) { space? >> dict_header.as(:dict_header) >> space >> 
    (definition >> space?).repeat.as(:definitions) }
  root(:program)
end

# Note on size:
# used in compilation step to actually organize memory contents
# size values actually need to depend on target architecture
# maybe better to use hash instead of methods

# Classes that are output by the parser transformations
class MFWord < Struct.new(:name)
  def size
    3
  end
end
class MFPrim < Struct.new(:name)
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
    # todo: include size of header
    1 + content.map(:size).reduce(:+)
  end
end

# Definition object, which can be moved into dictionary
class MFDefinition < Struct.new(:name,:definer,:effect,:body,:dictionary,:file)
  def syntax_word?
    definer == "SYNTAX:"
  end
  def normal_word?
    definer == ":"
  end
  # return printed location of definition
  def err_loc
    line,col=definer.line_and_column
    "#{file}:#{line}:#{col}"
  end
end

# named container for definitions
class MFDictionary < Struct.new(:name)
  attr_accessor :index
  def initialize(*args)
    super *args
    @index={}
  end
  def find(name)
    @index[name]
  end
  def add(definition)
    existing=@index[definition.name.to_s]
    raise "#{definition.err_loc}: Error: trying to add duplicate word #{definition.name.to_s}" if existing
    @index[definition.name.to_s]=definition
    definition.dictionary=self
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
  rule(:def => simple(:definer),
       :name => simple(:name),
       :effect => simple(:effect),
       :definition_body => subtree(:b)) { MFDefinition.new(name,definer,effect,b)}
  rule(:used_dict_name => simple(:dname)) { dname }
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
  def format_linecol(file,linecol)
    line,col=linecol
    "#{file}:#{line}:#{col}"
  end
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
    @files.each do |fname,defs|
      puts "analyzing #{fname}:"
      defs.each do |d|
        name = d[:name].to_s
        if existing=@defs[name]
          raise "word already exists: #{name}: #{existing[:body]}"
        else
          body = d[:definition_body]
          body.flatten.select{|e| e.is_a?(MFWord)}.each do |w|
            unless known_word? w
              raise "#{format_linecol(fname,w.name.line_and_column)}:unknown word: #{w.name} in #{name}"
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
