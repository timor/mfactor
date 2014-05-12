# ruby version of the mfactor interpreter, which can be used to
# cross-compile an image to c, amongst other things

require 'parslet'
require 'yaml'

class MFP < Parslet::Parser
  rule(:newline) { str("\n") >> str("\r").maybe }
  rule(:line_comment) { str('!') >> (newline.absent? >> any).repeat }
  rule(:space) { (line_comment | match('\s').repeat(1)).repeat }
  rule(:space?) { space.maybe }
  rule(:unsigned_dec) { match('[0-9]').repeat(1) }
  rule(:unsigned_hex) { str('0') >> match['xX'] >> match['0-9a-f'].repeat(1) }
  rule(:unsigned) { unsigned_hex | unsigned_dec }
  rule(:normal_word_char) { match['^\s:{\[\]};'] }
  rule(:normal_word) { normal_word_char.repeat(1) }
  rule(:sequence_opener_word) { normal_word_char.repeat(1) >> str('{') }
  rule(:definer_word) { normal_word_char.repeat(0) >> str(':') }
  rule(:def_end) { str(';') }
  rule(:word) { sequence_opener_word | definer_word | normal_word }
  rule(:char) { str("'") >> match["^'"].as(:char) >> str("'") }
  rule(:atom) { unsigned.as(:unsigned) | normal_word.as(:word) | char }
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
end
class MFPrim < MFWord
end
class MFDefinition < Struct.new(:definer, :name, :body)
end
class MFQuotation < Struct.new(:body)
end

class MFTransform < Parslet::Transform
  rule(:unsigned => simple(:num)) { Integer(num) }
  rule(:char => simple(:c)) { c.ord }
  rule(:string => simple(:s)) { s }
  rule(:word => simple(:name)) { MFactor.make_word(name) }
  rule(:quotation_body => sequence(:b)) {
    MFQuotation.new(b)}
  rule(:def => simple(:definer),
       :name => simple(:name),
       :effect => simple(:effect),
       :definition_body => sequence(:b)) { 
    MFDefinition.new(definer,name,b)}
end


class MFactor
  @@parser = MFP.new
  @@transform = MFTransform.new
  @@iset = Hash[YAML.load_file("instructionset.yml").map{ |cname,name|
                  [name==:private ? cname : name , cname ] }]
  def self.make_word(name)
    if @@iset[name] 
      MFPrim.new(@@iset[name])
    else
      MFWord.new(name)
    end
  end
  def initialize
    @files={}
    @current_file=nil
  end
  def parse(input)
    @@parser.parse(input)
  rescue Parslet::ParseFailed => failure
    puts "error while parsing #{@current_file}:"
    puts failure.cause.ascii_tree
  end
  def load_file(file)
    @current_file=file
    result=@@transform.apply(parse(File.read(file)))
    @files[file] = result
    result
  end
end

# def mfparse(str)
#   p=MFP.new
#   t=MFTransform.new
#   t.apply(p.parse(str))
# rescue Parslet::ParseFailed => failure
#   puts failure.cause.ascii_tree
# end

