require 'parslet'
require 'mfactor/datatypes'

module MFactor
  # parser class, will parse one source file when parse() method is
  # called
  class MFP < Parslet::Parser
    rule(:newline) { str("\n") >> str("\r").maybe }
    rule(:line_comment) { str('!') >> (newline.absent? >> any).repeat }
    rule(:space) { (line_comment | match('\s').repeat(1)).repeat }
    rule(:space?) { space.maybe }
    # rule(:unsigned_dec) { match('[0-9]').repeat(1) }
    # rule(:unsigned_hex) { str('0') >> match['xX'] >> match['0-9a-f'].repeat(1) }
    # rule(:unsigned) { unsigned_hex | unsigned_dec }
    rule(:normal_word_char) { match['^\s:{\[\]};'] }
    rule(:normal_word) { str(')').absent? >> normal_word_char.repeat(1) }
    rule(:sequence_opener_word) { normal_word_char.repeat(0) >> str('{') }
    rule(:definer_word) { normal_word_char.repeat(0) >> str(':') }
    rule(:def_end) { str(';') }
    rule(:wrapped_word) { str('\\') >> space >> normal_word.as(:wrapped_word_name) }
#    rule(:word) { wrapped_word | sequence_opener_word | definer_word | normal_word }
    rule(:char) { str("'") >> match["^'"].as(:char) >> str("'") }
    rule(:atom) { char | str("'").absent? >> normal_word.as(:word_or_number) }
    rule(:string) { str('"') >>
      ((str('\\')>>any)|(str('"').absent? >> any)).repeat(0).as(:string) >>
      str('"') }
    rule(:quotation_body) {
      ((quotation | fried_quotation | wrapped_word | string | literal_sequence | atom) >> space).repeat }
    rule(:literal_sequence) { sequence_opener_word.as(:seq_start) >> space >>
      quotation_body.as(:content) >> str('}') }
    rule(:fried_quotation) { str("'[") >> space >>
      quotation_body.as(:fried_quotation_body) >> str(']') }
    rule(:quotation) { str('[') >> space >>
      quotation_body.as(:quotation_body) >> str(']') }
    rule(:stack_effect_element) { normal_word.as(:effect_atom)>>
      ( str(':') >> space >> ( stack_effect | normal_word ).as(:effect_type)).maybe }
    rule(:stack_effect) { str('(') >> space >>
      ( str('--').absent? >>  stack_effect_element >> space ).repeat.as(:stack_input) >>
      str('--') >> space >>
      (str(')').absent? >> stack_effect_element >> space).repeat.as(:stack_output) >> str(')')}
    rule(:compiler_decl) { str('inline')|str('foldable')|str('flushable')|str('recursive')|str('nocompile') }
    rule(:definition) { definer_word.as(:def) >> space >>
      match('\S').repeat(1).as(:name) >> space >>
      (stack_effect.as(:effect) >> space) >>
      quotation_body.as(:definition_body) >> def_end >>
      (space >> compiler_decl.as(:definition_mod)).repeat(0).as(:definition_mods) }
    rule(:in_declaration) { str('IN:') >> space >> normal_word.as(:current_dict) }
    rule(:using_declaration) { str('USING:') >> space >>
      (normal_word.as(:used_dict_name) >> space).repeat >> str(';')}
    rule(:symbols_declaration) { str('SYMBOLS:') >> space >>
      (normal_word.as(:symbol_name) >> space).repeat >> str(';')}
    rule(:deferred_declaration) { str('DEFER:').as(:def) >> space >>
      normal_word.as(:deferred_name) }
    rule(:statement) { deferred_declaration | in_declaration | using_declaration.as(:using) |
      symbols_declaration.as(:symbols_decl) | definition }
    rule(:program) { space? >> (statement >> space?).repeat.as(:program) }
    root(:program)
  end

  # Note on size:
  # used in compilation step to actually organize memory contents
  # size values actually need to depend on target architecture
  # maybe better to use hash instead of methods

  # Classes that are output by the parser transformations

  # represents a word occurrence in the context of a number of executed words (e.g. definition body, or quotation body)

  class MFLitSequence
    attr_accessor :element_type
    attr_accessor :content
    attr_accessor :element_size
    def initialize(type,content)
      @content=content
      case type
      when "B{" then            # byte literals
        content.all? {|e| e.is_a?(MFByteLit) || raise( "#{e.err_loc}: not a byte literal: #{e}") } 
        @element_type=MFByteLit
        @element_size=1
      when "I{" then            # integer literals
        content.all? {|e| e.is_a?(MFIntLit) || raise("#{e.err_loc}: not an int literal: #{e}") }
        content.map{|e| MFIntLit.new(e.value)} # ensure int lit element class
        @element_size=4
        @element_type=MFIntLit
      else
        raise "unsupported literal sequence: '#{type}' }"
      end
    end
    def see
      lut={ MFByteLit => "#B{",
        MFIntLit => "#I{" }
      "#{lut[@element_type]} "+@content.map{|e| e.see}.join(" ") + " }"
    end
  end

  # general literal sequence opened by "{"
  class MFComplexSequence
    attr_accessor :content
    def initialize(content)
      @content = content
    end
    def [](i)
      @content[i]
    end
  end

  # represents a SYMBOLS: entry
  class SymbolsDecl < Struct.new(:names)
  end

  # represents a USING: entry
  class MFSearchPath < Struct.new(:vocabs)
  end

  # represents a change in current vocabulary
  class MFCurrentVocab < Struct.new(:vocab)
  end

  # use for getting rid of backslashes in names which had to be used to escape comment characters
  def unescape(s)
    case s
    when Parslet::Slice
      Parslet::Slice.new(s.position,s.str.gsub(/\\(\S)/,"\\1"),s.line_cache)
    when String
      str.gsub(/\\(\S)/,"\\1")
    end
  end
  module_function :unescape

  # tree transformation to output a structure that represents one file
  class MFTransform < Parslet::Transform
    # rule(:unsigned => simple(:lit)) {
    #   num=(Integer(lit))
    #   (num > 255 ? MFIntLit : MFByteLit).new(num)
    # }
    rule(:char => simple(:c)) { MFByteLit.new(c.to_s.ord) }
    rule(:string => simple(:s)) { MFStringLit.new(s.to_s) }
    rule(:word_or_number => simple(:name)) { if name.to_s =~ /^(0[xX][0-9a-fA-F]+|[0-9]+)$/
                                               num=Integer(name)
                                               (num > 255 ? MFIntLit : MFByteLit).new(num)
                                             else
                                               MFWord.new(name.to_s) # BUG: not supposed to convert to string here
                                             end
    }
    rule(:quotation_body => subtree(:b)) { Quotation.new(b) }
    rule(:fried_quotation_body => subtree(:b)) { FriedQuotation.new(b) }
    rule(:seq_start=>simple(:opener), :content => subtree(:content)) {
      if opener.str == "{"
        MFComplexSequence.new(content)
      else
        MFLitSequence.new(opener,content)
      end}
    rule(:definition_mod => simple(:modname)) {modname}
    rule(:stack_input => subtree(:inp),
         :stack_output => subtree(:outp)) { StackEffect.new(inp,outp) }
    rule(:effect_atom => simple(:a),
         :effect_type => subtree(:type)) {MFEffectItem.new(a,type)}
    rule(:effect_atom => simple(:a)) {MFEffectItem.new(a,:t)}
    rule(:effect_quotation => subtree(:more)) {more}
    rule(:def => simple(:definer),
         :name => simple(:name),
         :effect => subtree(:effect),
         :definition_body => subtree(:body),
         :definition_mods => sequence(:mods)) { MFDefinition.new(MFactor::unescape(name),definer,effect,Quotation.new(body),mods)}
    rule(:used_dict_name => simple(:dname)) { dname }
    rule(:using => simple(:junk)) { MFSearchPath.new([]) }
    rule(:using => sequence(:vocabs)) {MFSearchPath.new(vocabs)}
    rule(:wrapped_word_name => simple(:n)) {WrappedWord.new(n.to_s)}
    rule(:symbol_name => simple(:n)) { n }
    rule(:symbols_decl => sequence(:names)) {SymbolsDecl.new(names)}
    rule(:def => simple(:definer),
         :deferred_name => simple(:name)) {MFDefinition.new(MFactor::unescape(name),definer,nil,Quotation.new([]))}
    rule(:current_dict => simple(:vocab)) {MFCurrentVocab.new(vocab.to_s)}
    rule(:program => subtree(:p)) { p }
  end

  def unparse(tree)
    case tree
    when MFDefinition
      tree.definer.to_s << " " << tree.name.to_s << " " <<
        unparse(tree.effect) << "\n" <<
        tree.code.body.map{|c| unparse(c)}.join(" ") << " ;\n"
    when StackEffect
      "( " << tree.inputs.map{|i| unparse(i)}.join(" ") << " -- " <<
        tree.outputs.map{|i| unparse(i)}.join(" ") << " )"
    when MFEffectItem
      tree.name.to_s
    when Quotation
      "[ " << tree.body.map{|c| unparse(c)}.join(" ") << " ]\n"
    when MFWord
      tree.name.to_s
    when MFIntLit
      tree.value.to_s
    when MFStringLit
      '"' << tree.value.to_s << '"'
    when MFLitSequence
      "{ " << tree.content.map{c| unparse(c)}.join(" ") << " }\n"
    when MFComplexSequence
      "{ " << tree.content.map{c| unparse(c)}.join(" ") << " }\n"
    else
      "<# #{tree.class} >"
    end
  end
  module_function :unparse
end
