require 'parslet'

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
    rule(:sequence_opener_word) { normal_word_char.repeat(1) >> str('{') }
    rule(:definer_word) { normal_word_char.repeat(0) >> str(':') }
    rule(:def_end) { str(';') }
    rule(:word) { sequence_opener_word | definer_word | normal_word }
    rule(:char) { str("'") >> match["^'"].as(:char) >> str("'") }
    rule(:atom) { char | str("'").absent? >> normal_word.as(:word_or_number) }
    rule(:string) { str('"') >>
      ((str('\\')>>any)|(str('"').absent? >> any)).repeat(0).as(:string) >>
      str('"') }
    rule(:quotation_body) {
      ((quotation | string | literal_sequence | atom) >> space).repeat }
    rule(:literal_sequence) { sequence_opener_word.as(:seq_start) >> space >>
      quotation_body.as(:content) >> str('}') }
    rule(:quotation) { str('[') >> space >>
      quotation_body.as(:quotation_body) >> str(']') }
    rule(:stack_effect_element) { normal_word.as(:effect_atom)>>
      ( str(':') >> space >> ( stack_effect | normal_word ).as(:effect_type)).maybe }
    rule(:stack_effect) { str('(') >> space >>
      ( str('--').absent? >>  stack_effect_element >> space ).repeat.as(:stack_input) >>
      str('--') >> space >>
      (str(')').absent? >> stack_effect_element >> space).repeat.as(:stack_output) >> str(')')}
    rule(:compiler_decl) { str('inline')|str('foldable')|str('flushable')|str('recursive') }
    rule(:definition) { definer_word.as(:def) >> space >>
      match('\S').repeat(1).as(:name) >> space >>
      (stack_effect.as(:effect) >> space) >>
      quotation_body.as(:definition_body) >> def_end >>
      (space >> compiler_decl.as(:definition_mod)).repeat(0).as(:definition_mods) }
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
  class MFWord < Struct.new(:name,:definition,:is_tail)
    def initialize(*a)
      super *a
      @file=$current_mfactor_file
    end
    def see
      name.to_s.downcase
    end
    def err_loc
      line,col=name.line_and_column
      "#{@file}:#{line}:#{col}"
    end
    def change_name(newname)
      old=name
      name=Parslet::Slice.new(old.position,newname,old.line_cache)
    end
  end

  class MFIntLit < Struct.new(:value)
    def see
      "#I#{value}"
    end
  end
  class MFByteLit < MFIntLit
    def see
      "#B#{value}"
    end
  end

  class MFLitSequence
    attr_accessor :element_type
    attr_accessor :content
    attr_accessor :element_size
    def initialize(type,content)
      @content=content
      case type
      when "B{" then
        content.all? {|e| e.is_a?(MFByteLit) || raise( "#{e.err_loc}: not a byte literal: #{e}") } 
        @element_type=MFByteLit
        @element_size=1
      when "I{" then
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

  # Definition object, which can be moved into dictionary
  class MFDefinition < Struct.new(:name,:definer,:effect,:body,:mods,:vocabulary,:file)
    def initialize(*args)
      super(*args)
      convert_tailcalls(body)
    end
    def syntax_word?
      definer == "SYNTAX:"
    end
    def normal_word?
      definer == ":"
    end
    def primitive?
      definer == "PRIM:"
    end
    def inline?
      mods.member? "inline"
    end
    # return printed location of definition
    def err_loc
      line,col=definer.line_and_column
      "#{file}:#{line}:#{col}"
    end
    def see
      ": #{name} #{effect} "+
        body.map{ |elt| see_word(elt) }.join(" ")
    end
    # TODO: move out of here, into emitter
    def convert_tailcalls(b)
      if b[-1].is_a? MFWord
        b[-1].is_tail = true
        # puts "#{b[-1].err_loc}:Info: tailcall"
      end
      b.each do |elt|
        if elt.is_a?(Array)
          convert_tailcalls(elt)
        end
      end
    end
  end

  # represents a USING: entry
  class MFSearchPath < Struct.new(:vocabs)
  end

  # represents a change in current vocabulary
  class MFCurrentVocab < Struct.new(:vocab)
  end

  class MFEffectItem < Struct.new(:name,:type)
  end

  # tree transformation to output a structure that represents one file
  class MFTransform < Parslet::Transform
    # rule(:unsigned => simple(:lit)) {
    #   num=(Integer(lit))
    #   (num > 255 ? MFIntLit : MFByteLit).new(num)
    # }
    rule(:char => simple(:c)) { MFByteLit.new(c.to_s.ord) }
    rule(:string => simple(:s)) { s.to_s }
    rule(:word_or_number => simple(:name)) { if name.to_s =~ /^(0[xX][0-9a-fA-F]+|[0-9]+)$/
                                               num=Integer(name)
                                               (num > 255 ? MFIntLit : MFByteLit).new(num)
                                             else
                                               MFWord.new(name)
                                             end
    }
    rule(:quotation_body => subtree(:b)) { b }
    rule(:seq_start=>simple(:opener), :content => subtree(:content)) {
      MFLitSequence.new(opener,content) }
    rule(:definition_mod => simple(:modname)) {modname}
    rule(:stack_input => subtree(:inp),
         :stack_output => subtree(:outp)) { [inp,outp] }
    rule(:effect_atom => simple(:a),
         :effect_type => subtree(:type)) {MFEffectItem.new(a,type)}
    rule(:effect_atom => simple(:a)) {MFEffectItem.new(a,:t)}
    rule(:effect_quotation => subtree(:more)) {more}
    rule(:def => simple(:definer),
         :name => simple(:name),
         :effect => subtree(:effect),
         :definition_body => subtree(:body),
         :definition_mods => sequence(:mods)) { MFDefinition.new(name,definer,effect,body,mods)}
    rule(:used_dict_name => simple(:dname)) { dname.to_s }
    rule(:using => simple(:junk)) { MFSearchPath.new([]) }
    rule(:using => sequence(:vocabs)) {MFSearchPath.new(vocabs.map{|v| v.to_s})}
    rule(:current_dict => simple(:vocab)) {MFCurrentVocab.new(vocab.to_s)}
    rule(:program => subtree(:p)) { p }
  end
end
