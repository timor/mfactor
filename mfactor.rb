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
  rule(:quotation_body) {
    ((quotation | string | literal_sequence | atom) >> space).repeat }
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
  rule(:using_declaration) { str('USING:') >> space >> 
    (normal_word.as(:used_dict_name) >> space).repeat >> str(';')}
  rule(:statement) { in_declaration | using_declaration.as(:using) | definition }
  rule(:program) { space? >> (statement >> space?).repeat.as(:program) }
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
  attr_accessor :element_type
  attr_accessor :content
  def initialize(type,content)
    @content=content
    case type
    when "B{" then
      content.all? {|e| e.is_a?(MFByteLit) || raise( "not a byte literal: #{e}") } 
      @element_type=MFByteLit
    when "I{" then
      content.all? {|e| e.is_a?(MFIntLit) || raise("not an int literal: #{e}") }
      content.map{|e| MFIntLit.new(e.value)} # ensure int lit element class
      @element_type=MFIntLit
    else
      raise "unsupported literal sequence: '#{type}' }"
    end
  end
end

# Definition object, which can be moved into dictionary
class MFDefinition < Struct.new(:name,:definer,:effect,:body,:vocabulary,:file)
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

# represents a USING: entry
class MFSearchPath < Struct.new(:vocabs)
end

# represents a change in current vocabulary
class MFCurrentVocab < Struct.new(:vocab)
end

require 'pp'
# named container for definitions
class MFVocabulary
  attr_accessor :name
  attr_accessor :definitions
  def initialize(name)
    @name=name
    @index={}
    @definitions=[]
  end
  def find(name)
    @index[name]
  end
  def add(definition)
    existing=@index[definition.name.to_s]
    raise "#{definition.err_loc}: Error: trying to add duplicate word #{definition.name.to_s}" if existing
    @index[definition.name.to_s]=definition
    definition.vocabulary = self  # doubly link
    @definitions.push(definition)
  end
end

# tree transformation to output a structure that represents one file
class MFTransform < Parslet::Transform
  rule(:unsigned => simple(:lit)) {
    num=(Integer(lit))
    (num > 255 ? MFIntLit : MFByteLit).new(num)
  }
  rule(:char => simple(:c)) { MFByteLit.new(c.to_s.ord) }
  rule(:string => simple(:s)) { s.to_s }
  rule(:word => simple(:name)) { (ISET[name.to_s] ? MFPrim : MFWord).new(name) }
  rule(:quotation_body => subtree(:b)) { b }
  rule(:seq_start=>simple(:opener), :content => subtree(:content)) {
    MFLitSequence.new(opener,content) }
  rule(:def => simple(:definer),
       :name => simple(:name),
       :effect => simple(:effect),
       :definition_body => subtree(:b)) { MFDefinition.new(name,definer,effect,b)}
  rule(:used_dict_name => simple(:dname)) { dname.to_s }
  rule(:using => simple(:junk)) { MFSearchPath.new([]) }
  rule(:using => sequence(:vocabs)) {MFSearchPath.new(vocabs)}
  rule(:current_dict => simple(:vocab)) {MFCurrentVocab.new(vocab.to_s)}
  rule(:program => subtree(:p)) { p }
end

# used to build up an application image composed of multiple source files
class MFactor
  attr_accessor :dictionaries
  @@parser = MFP.new
  @@transform = MFTransform.new
  def initialize
    @files=[]                   # keep track of loaded files
    @current_file=nil
    @dictionary={}
    @vocab_roots=[File.expand_path(File.dirname(__FILE__)+"/lib")]
    @current_vocab=nil
    @search_vocabs=[]
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
  def parse_file(file)
    @current_file=file
    puts "parsing #{file}"
    STDOUT.flush
    result=@@transform.apply(parse(File.read(file)))
    # pp result
    result
  end
  # check if word is known by name in search path, return definition if found
  # TODO check search path search order
  def find_name(name)
    searchlist=@dictionary.values
    searchlist.each do |vocab|
      if found=vocab.find(name)
        # puts "found word: #{found}"
        return found
      end
    end
    nil
  end
  # return existing or add
  def get_vocabulary_create(name)
    unless @dictionary[name.to_s]
      @dictionary[name.to_s] = MFVocabulary.new(name.to_s)
    end
    @dictionary[name.to_s]
  end
  def find_vocab_file(vocab_name)
    @vocab_roots.map{|path| Dir.glob("#{path}/#{vocab_name}.mfactor")}.flatten.first ||
      raise("vocabulary not found: #{vocab_name} (in #{@current_file})")
  end
  # try to load one vocabulary
  def load_vocab (vocab_name)
    file=find_vocab_file(vocab_name)
    if @files.member?(file)
      return @dictionary[vocab_name]||raise("file '#{file}' loaded, but no vocabulary '#{vocab_name} found!")
    end
    puts "trying to load '#{vocab_name}.mfactor'"
    program=parse_file(file)
    # step through every definition
    program.each do |d|
      case d
        # IN: directive
      when MFCurrentVocab then
        puts "define vocab: #{d.vocab}"
        @current_vocab=get_vocabulary_create(d.vocab)
        @dictionary[d.vocab]=@current_vocab
        # USING: deirective
      when MFSearchPath then
        # TODO: save search path when diving into different file
        d.vocabs.each do |v|
          puts "maybe load #{v}"
          load_vocab(v) unless @dictionary[v]
          puts "done loading #{v}"
          @search_vocabs.unshift(@dictionary[v]) unless @search_vocabs.member?(@dictionary[v])
        end
        puts "file:#{file} searchpath:"
        pp @search_vocabs.map{|v| v.name}
      when MFDefinition then
        d.file=file
        name = d.name.to_s
        raise "#{d.err_loc}:Error: word already exists: #{name}" if find_name(name)
        @current_vocab.add d    # need to add here because of recursion
        d.body.select{|w| w.is_a?(MFWord)}.each do |word|
          wname=word.name.to_s
          raise "#{d.err_loc}:Error: word '#{wname}' not found on #{@search_vocabs.map{|s| s.name}}" unless find_name(wname)
        end
      else
        raise "don't know how to load program item #{d}"
      end
    end
  end
end


# def mfparse(str)
#   p=MFP.new
#   t=MFTransform.new
#   t.apply(p.parse(str))
# rescue Parslet::ParseFailed => failure
#   puts failure.cause.ascii_tree
# end
