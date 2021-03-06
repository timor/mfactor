# ruby version of the mfactor interpreter, which can be used to
# cross-compile an image to c, amongst other things

require 'rubygems'
require 'bundler/setup'

require 'yaml'

$mf_verbose= defined?(Rake) ? Rake.verbose : nil

require 'mfactor/parser'
require 'mfactor/vocab'

# TODO: replace ISET with all loaded primitives, used in bytecode compiler
ISET=Hash[YAML.load_file(File.dirname(__FILE__)+"/../../instructionset.yml").map{ |cname,name|
            [name==:private ? cname : (name || cname) , cname ] }]
puts "Instruction Set: #{ISET}" if $mf_verbose==true

module MFactor

  def see_word(elt)
    case elt
    when Quotation then "[ "+ elt.body.map{|e| see_word(e)}.join(" ") + " ]"
    when String then '"'+elt+'"'
    else elt.see
    end
  end
  module_function :see_word
  require 'pp'

  $current_mfactor_file=nil

  # used to build up an application image composed of multiple source files
  class Image
    attr_accessor :dictionary   # contains name -> Vocabulary pairs
    attr_accessor :vocab_roots
    attr_accessor :files
    @@parser = MFP.new
    @@transform = MFTransform.new
    def initialize(roots)
      @files=[]                   # keep track of loaded files
      # @current_file=nil
      @dictionary={"kernel"=>Vocabulary.new("kernel")}
      @vocab_roots=[*roots,File.expand_path(File.dirname(__FILE__)+"/../../src/mfactor")]
      @filestack = []
      puts "vocab load path: #{@vocab_roots}" if $mf_verbose
    end
    # call the parser on an input object (file)
    def format_linecol(file,linecol)
      line,col=linecol
      "#{file}:#{line}:#{col}"
    end
    def see
      @dictionary.values.each do |vocab|
        puts vocab.see
      end
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
        puts "#{$current_mfactor_file}:#{line}:#{col}: Error: #{cause.to_s}"
      end
      rec_print(cause)
      puts failure.cause.ascii_tree
      raise
    end
    def parse_file(file)
      $current_mfactor_file=file
      puts "parsing '#{file}'" if $mf_verbose
      STDOUT.flush
      result=@@transform.apply(parse(File.read(file)))
      # pp result
      result
    end
    # check if word is known by name in search path, return definition if found
    def find_name(name,search_vocabs=@dictionary.values)
      # search_vocabs ||= @dictionary.values
      search_vocabs.each do |vocab|
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
        @dictionary[name.to_s] = Vocabulary.new(name.to_s)
      end
      @dictionary[name.to_s]
    end
    def find_vocab_file(vocab_name)
      res = @vocab_roots.map{|path| Dir.glob("#{path}/#{vocab_name.to_s}.mfactor")}.flatten.first
      unless res
        line,col=vocab_name.line_and_column
        raise("#{@filestack[-1]}:#{line}:#{col}:Error: vocabulary not found: '#{vocab_name}'")
      end
      res
    end
    def word_assign_definition(word, current_vocab, search_vocabs)
      wname=word.name.to_s
      def_of_w = find_name(wname,[current_vocab]+search_vocabs)
      raise "#{word.err_loc}:Error: word '#{wname}' not found on #{search_vocabs.map{|s| s.name}}" unless def_of_w
      word.definition=def_of_w
      return def_of_w
    end
    # recursively scan through quotation, checking if words can be found (thereby
    # associating a defininiton), expanding force-inlined definitions and expanding fried
    # quotations
    def expand_body(body, current_vocab, search_vocabs)
      body.each_with_index do |elt, i|
        # maybe replace next word by inline definition
        if elt.is_a? MFWord
          d=word_assign_definition(elt,current_vocab, search_vocabs)
          if d.forced_inline
            new_code = d.code.body.dup
            # inline body, continue with new code
            body.delete(i)
            body.insert i, *new_code
            elt = body[i]
          end
        end
        #non-inline dispatch
        case elt
        when MFWord then word_assign_definition(elt,current_vocab, search_vocabs)
        when Quotation then expand_body(elt.body, current_vocab, search_vocabs)
        when MFComplexSequence then expand_body(elt.content, current_vocab, search_vocabs)
        when Literal then           # skip literals
        when MFLitSequence then     # skip literals
        when WrappedWord then       # skip wrapped words, they are handled later
        else raise "unable to expand item: #{elt}"
        end
      end
    end
    # load one colon definition
    def load_def (d,file,current_vocab,search_vocabs)
      d.file=file
      name = d.name.to_s
      if old_def=find_name(name,[current_vocab] + search_vocabs)
        unless old_def.deferred?
          raise "#{d.err_loc}:Error: word already exists: #{name}
#{old_def.err_loc}:Note: Location of previous definition"
        end
      end
      # hack: assume kernel vocab is present, add all primitives to kernel
      if d.primitive?
        @dictionary["kernel"].add d
      end
      current_vocab.add d    # need to add here because of recursion
      # find all used words in vocabularies, force inline any if necessary
      expand_body(d.code.body, current_vocab, search_vocabs)
    end
    # try to load one vocabulary
    def load_vocab (vocab_name)
      current_vocab=nil
      search_vocabs=[]
      $definition_linecomment = nil   # last line comment
      file=find_vocab_file(vocab_name)
      @filestack.push(file)
      if @files.member?(file)
        return @dictionary[vocab_name.to_s]||raise("file '#{file}' loaded, but no vocabulary '#{vocab_name} found!")
      end
      puts "trying to load '#{vocab_name}.mfactor'" if $mf_verbose == true
      program=parse_file(file)
      # step through every definition
      program.each do |d|
        case d                    # IN: directive
        when MFCurrentVocab then
          puts "define vocab: #{d.vocab}" if $mf_verbose == true
          current_vocab=get_vocabulary_create(d.vocab)
          current_vocab.used_vocabs = search_vocabs.dup
          if current_vocab.definition_file and current_vocab.definition_file != file
            puts "WARNING: vocab #{current_vocab.name} has file associated: #{current_vocab.definition_file},
associating with #{file} now!"
          end
          puts "assigning #{file} to vocab #{current_vocab.name}" if $mf_verbose == true
          current_vocab.definition_file = file
          @dictionary[d.vocab.to_s]=current_vocab
        when MFSearchPath then    # USING: directive
          search_vocabs=[]
          d.vocabs.each do |v|
            if @dictionary[v.to_s] && !(@dictionary[v.to_s].definitions.empty?)
              puts "#{v} already loaded" if $mf_verbose == true
            else
              puts "loading #{v}" if $mf_verbose == true
              load_vocab(v)
              puts "done loading #{v}" if $mf_verbose == true
            end
            raise "no dictionary entry for vocab '#{v}'" unless @dictionary[v.to_s]
            search_vocabs.unshift(@dictionary[v.to_s])
          end
          puts "file: #{file}\n searchpath:" if $mf_verbose == true
          pp search_vocabs.map{|v| v.name} if $mf_verbose == true
        when MFDefinition then
          if d.deferred?
            puts "deferring: #{d.name}" if $mf_verbose == true
            load_def(d,file,current_vocab,search_vocabs)
          else
            puts "defining: #{d.name}" if $mf_verbose == true
            load_def(d,file,current_vocab,search_vocabs)
          end
          d.description = $last_comment if $last_comment
          $last_comment = nil
        # expand SYMBOLS: declaration
        when SymbolsDecl then
          d.names.each do |name|
            puts "defining symbol: #{name}" if $mf_verbose == true
            sym_def = MFDefinition.new(name,
                                       Parslet::Slice.new(name.position,":",name.line_cache),
                                       StackEffect.new([],[MFEffectItem.new("sym",:sym)]),
                                       Quotation.new([WrappedWord.new(name.to_s)]),
                                       [])
            load_def(sym_def,file,current_vocab,search_vocabs)
          end
        when Comment then
          $last_comment = d.content
        else
          raise "don't know how to load program item #{d}"
        end
      end
      @filestack.pop
    end
  end
end
