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
    when Array then "[ "+ elt.map{|e| see_word(e)}.join(" ") + " ]"
    when String then '"'+elt+'"'
    else elt.see
    end
  end
  module_function :see_word
  require 'pp'

  $current_mfactor_file=nil

  # used to build up an application image composed of multiple source files
  class Image
    attr_accessor :dictionary
    attr_accessor :vocab_roots
    attr_accessor :files
    @@parser = MFP.new
    @@transform = MFTransform.new
    def initialize(roots)
      @files=[]                   # keep track of loaded files
      # @current_file=nil
      @dictionary={"kernel"=>Vocabulary.new("kernel")}
      @vocab_roots=[*roots,File.expand_path(File.dirname(__FILE__)+"/../../src/mfactor")]
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
      puts "parsing #{file}" if $mf_verbose
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
      @vocab_roots.map{|path| Dir.glob("#{path}/#{vocab_name}.mfactor")}.flatten.first ||
        raise("vocabulary not found: #{vocab_name} (in #{$current_mfactor_file})")
    end
    # try to load one vocabulary
    def load_vocab (vocab_name)
      current_vocab=nil
      search_vocabs=[]
      file=find_vocab_file(vocab_name)
      if @files.member?(file)
        return @dictionary[vocab_name]||raise("file '#{file}' loaded, but no vocabulary '#{vocab_name} found!")
      end
      puts "trying to load '#{vocab_name}.mfactor'" if $mf_verbose == true
      program=parse_file(file)
      # step through every definition
      program.each do |d|
        case d                    # IN: directive
        when MFCurrentVocab then
          puts "define vocab: #{d.vocab}" if $mf_verbose == true
          current_vocab=get_vocabulary_create(d.vocab)
          @dictionary[d.vocab]=current_vocab
        when MFSearchPath then    # USING: directive
          search_vocabs=[]
          d.vocabs.each do |v|
            if @dictionary[v] && !(@dictionary[v].definitions.empty?)
              puts "#{v} already loaded" if $mf_verbose == true
            else
              puts "loading #{v}" if $mf_verbose == true
              load_vocab(v)
              puts "done loading #{v}" if $mf_verbose == true
            end
            search_vocabs.unshift(@dictionary[v])
          end
          puts "file:#{file}\n searchpath:" if $mf_verbose == true
          pp search_vocabs.map{|v| v.name} if $mf_verbose == true
        when MFDefinition then
          d.file=file
          name = d.name
          if old_def=find_name(name,[current_vocab] + search_vocabs)
            raise "#{d.err_loc}:Error: word already exists: #{name}
#{old_def.err_loc}:Note: Location of previous definition"
          end
          # hack: assume kernel vocab is present, add all primitives to kernel
          if d.primitive?
            @dictionary["kernel"].add d
          end
          current_vocab.add d    # need to add here because of recursion
          # find all used words in vocabularies
          d.body.flatten.select{|w| w.is_a?(MFWord)}.each do |word|
            wname=word.name
            def_of_w = find_name(wname,[current_vocab]+search_vocabs)
            raise "#{d.err_loc}:Error: word '#{wname}' not found on #{search_vocabs.map{|s| s.name}}" unless def_of_w
            word.definition=def_of_w
            # puts "word #{word.name} has def in \nFile:#{word.definition.err_loc}"
          end
        else
          raise "don't know how to load program item #{d}"
        end
      end
    end
  end
end
