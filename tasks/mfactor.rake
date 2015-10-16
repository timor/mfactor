# -*- mode:ruby -*-

require 'yaml'
require 'tempfile'
# set up load path
$:.unshift(File.join(File.dirname(__FILE__),"..","lib"))
require_relative '../lib/mfactor/analyze'
require_relative '../lib/mfactor/c_emitter'

$mfactor_image = nil            # this holds the ruby object after the image has been
                                # built, can be used by other rake files

THISDIR=File.dirname(__FILE__)
ISETFILE=File.join(THISDIR,"../instructionset.yml")
TRANSLATION_YAML_FILE ||= nil
# make target application's object file depend on the generated stuff
MFACTOR_DEPENDING_OBJECTS ||= ["mfactor/src/interpreter.c"]
# can be a hash table that contains pairs of the form (mfactor-word -> name-of-c-define)
MFACTOR_C_WORDS ||= {}
MFACTOR_IMAGE_SECTION ||= nil
MFACTOR_DICT_SECTION ||= nil
puts "no c translations" if MFACTOR_C_WORDS == {}
INSTBASE=
  if GENERATOR == "Cortex"
    0xa0
  elsif GENERATOR == "Linux64"
    0x80
  end
SRC_REPO_PREFIX ||= ""          # prefix for generating the linked graph

# generate the mfactor side of the ff code
def ff_mfactor (yaml,out)
  i=0;
  out << <<END
USING: kernel ;
IN: ff
END
  yaml.each do |cname,opts|
    mfname= opts["name"]
    callspec= opts["call"]
    call = callspec ? "ccall_"+callspec : "" ; # if no call, then taken as literal (e.g. variable access)
    effect_input = ""
    if (callspec != "lit") && (callspec != "v") then
      effect_input = callspec.chars.to_a.join " "
    end
    out << <<END
: #{mfname} ( #{effect_input} -- res ) #{i} ff #{call} ;
END
    i += 1;
  end
end

# generate c code for yaml
def ff_code (yaml,out)
  # puts yaml.inspect
  yaml.each do |cname,opts|
    out << "extern void* #{cname};\n"
  end
  out << "#define FF_LENGTH #{yaml.length}\n"
  out << "cell FF_Table[#{yaml.length}] = {\n"
  yaml.each do |cname,opts|
    out << "(cell)&#{cname},\n"
  end
    out << "};\n"
end

directory "generated"

require "mfactor/bytecode"

# main code generation routine

def build_image
  puts "rebuilding image from generated sources"
  if defined? MFACTOR_FF
    ffyaml=YAML.load_file(MFACTOR_FF)
    ff_mfactor(ffyaml,File.open("generated/ff.mfactor","w"))
  end
  # iset=YAML.load_file("#{THISDIR}/instructionset.yml")
  # stdlib=YAML_Mfactor.new("generated/mfactor.yml",iset)
  mf=MFactor::ByteCode.const_get(GENERATOR).new([MFACTOR_SRC_DIR,"generated"])
  mf.load_vocab(MFACTOR_ROOT_VOCAB)
  write_dot_dependencies(mf, File.open("generated/all_dependencies.dot","w"), false)
  write_dot_dependencies(mf, File.open("generated/app_dependencies.dot","w"), true)
  File.open("generated/image_size.h","w") do |f|
    f.puts "#define IMAGE_SIZE #{mf.bytecode_size}"
    # define the starting word for use in interpreter() call
    f.puts "#define START_WORD_OFFSET " + (mf.get_word_address(START_WORD)).to_s
  end
  section_prefix = if MFACTOR_IMAGE_SECTION
                     "__attribute__((section(\".#{MFACTOR_IMAGE_SECTION}\"))) "
                   else
                     ""
                   end
  File.open("generated/image.code.h","w") do |f|
    ff_code(ffyaml || [],f)
    f.write "#{section_prefix}inst image[#{mf.bytecode_size}]= {\n"
    mf.write_bytecode_image f
    f.write "};\n"
  end
  section_prefix = if MFACTOR_DICT_SECTION
                     "__attribute__((section(\".#{MFACTOR_DICT_SECTION}\"))) "
                   else
                     ""
                   end
  File.open("generated/image.dict.h","w") do |f|
    f.write "#{section_prefix} dict_entry dict[VM_DICT] __attribute((aligned(1))) = {\n"
    mf.write_dictionary_entries f
    f.write "};\n"
    mf.write_hash_table f
  end
  File.open("generated/mfactor_words.h","w") do |f|
    f.puts "extern char image[];"
    mf.write_word_positions(MFACTOR_C_WORDS,f)
  end
  mf
end

desc "output parser and transformation result of [arg]"
task :parse, :path do |t,args|
  raise "usage: rake parse[filename]" unless args[:path]
  raise "unknown file #{args[:path]}" unless File.exist?(args[:path])
  res=MFactor::MFP.new.parse(File.read(args[:path]))
  pp res
  res=MFactor::MFTransform.new.apply(res)
  pp res
  res.each do |e|
    puts MFactor::unparse(e),"\n"
  end
end

desc "show the mfactor dictionary"
task :see_dict => "generated" do
  puts build_image.see
end

IMAGE_FILES=["generated/image.code.h","generated/image.dict.h","generated/image_size.h","generated/mfactor_words.h"]
# file "generated/_generated_" => IMAGE_FILES+["generated/inst_enum.h"] do
#   touch "generated/_generated_"
# end

# requesting any of the to-be-generated files triggers generation of all
IMAGE_FILES.each do |f|
  file f => ["generated","#{ISETFILE}"]+FileList["#{THISDIR}/../src/mfactor/*.mfactor"]+FileList["#{MFACTOR_SRC_DIR}/*.mfactor"] do
    $mfactor_image = build_image
  end
  if defined? MFACTOR_FF
    file f => MFACTOR_FF
  end
end

if MFACTOR_DEPENDING_OBJECTS
  MFACTOR_DEPENDING_OBJECTS.each do |f|
    file f => IMAGE_FILES
    file f => "generated/inst_enum.h"
  end
end


file "generated/inst_enum.h" => ["#{ISETFILE}"] do
  puts "updating instruction set"
  iset=YAML.load_file("#{ISETFILE}")
  File.open("generated/inst_enum.h","w") do |f|
    f.puts "enum inst_set {\n"
    i=INSTBASE
    iset.each do |mnem,name| 
      name ||= mnem
      f.puts <<END
/* #{name} */
#{mnem} = 0x#{i.to_s(16)},

END
      i+=1
    end
    f.puts "};"
  end
end

desc "build the mfactor code"
task :mfactor => IMAGE_FILES+[__FILE__]

require 'pp'

task :mftest, :word do |t,args|
  $stdout.sync=true
  mf=MFactor::ByteCode.const_get(GENERATOR).new([MFACTOR_SRC_DIR,"generated"])
  mf.load_vocab(MFACTOR_ROOT_VOCAB)
  a=MFactor::MFStaticCompiler.new(mf)
  # pp a.infer_word(args[:word])
  dotfile=Tempfile.new("_mftestgraph_dot")
  d=mf.find_name(args[:word])
  raise "unknown definition: '#{args[:word]}'" unless d
  a.definition_dot_graph(mf.find_name(args[:word]),dotfile)
  dotfile.close
  cp dotfile.path, "generated/test.dot"
#  sh "dot -Tpng #{dotfile.path} -o generated/test.png "
  sh "dot -Tpng generated/test.dot -o generated/test.png "
end
task :mftest => "generated"

directory "generated/cfg"
directory "generated/ccode"

def write_dot_dependencies(mf, out, no_core)
  skip_vocabs = []
  out.puts "digraph deps {"
  mf.dictionary.each do |name, vocab|
    puts "outputting deps for #{name}"
    if vocab.definition_file
      defpath= Pathname.new(vocab.definition_file)
      if defpath.absolute?
        if no_core
          puts "adding #{vocab.name} to ignore list for output"
          skip_vocabs.push vocab
          next
        end
      else
        # only output local stuff
        # defpath=defpath.relative_path_from(Pathname.new(Dir.pwd))
        url=SRC_REPO_PREFIX+"/"+defpath.to_s
        out.puts "\"#{name}\"[URL=\"#{url}\", target=\"_blank\", fontcolor=\"blue\"]"
      end
    end
    vocab.used_vocabs.each do |v|
      out.puts "\"#{name}\" -> \"#{v.name}\"" unless skip_vocabs.member?(v)
    end
  end
  out.puts "}"
end

# iterate through all vocabularies
# generate a subdir in generated for each vocabulary, generate a control flow graphic for each word, if applicable
task :compile_all => ["generated/cfg","generated/ccode"] do
  $stdout.sync=true
  if defined? MFACTOR_FF
    ffyaml=YAML.load_file(MFACTOR_FF)
    ff_mfactor(ffyaml,File.open("generated/ff.mfactor","w"))
  end
  mf=MFactor::Image.new([MFACTOR_SRC_DIR,"generated"])
  mf.load_vocab(MFACTOR_ROOT_VOCAB)
  a=MFactor::MFStaticCompiler.new(mf)
  puts "translation file: #{TRANSLATION_YAML_FILE}" if TRANSLATION_YAML_FILE
  e=MFactor::CEmitter.new(TRANSLATION_YAML_FILE ? YAML.load_file(TRANSLATION_YAML_FILE) : nil)
  mf.dictionary.each do |name,vocab|
    dir="generated/cfg/#{name}"
    mkdir_p dir
    vocab.definitions.each do |d|
      next unless d.compilable?
      begin
        dotfname=dir+"/#{MFactor::filename_escape(d.name)}.dot"
        begin
          dotfile= File.new(dotfname,"w")
          a.definition_dot_graph d, dotfile
        ensure
          dotfile.close
        end
      rescue MFactor::UncompilableError => msg
        puts "#{d.err_loc}:Warning: cannot compile '#{d.name}', reason: "
        puts msg
      rescue MFactor::CompileError => msg
        puts "#{d.err_loc}:Error While compiling `#{d.name}`:"
        puts msg
        puts "Compilation Log:"
        puts d.compile_log
        raise
      rescue Exception
        puts "general Exception! Compilation Log:"
        puts d.compile_log
        raise
      ensure
        begin                   # if dot fails, tell so and contiue
          sh "dot -Tpng #{dotfname} -o #{dotfname.ext('png')} " if File.exist?(dotfname)
          File.open(dotfname.ext('log'),"w") do |f|
            f.puts d.compile_log
          end
        rescue
          puts "unable to produce graph"
        end
      end
    end
    # call the c code emitter for all vocabularies
    cfile="generated/ccode/#{name}.c"
    f= File.open(cfile,"w")
    begin
      vocab.definitions.each do |d|
        c=""
        begin
          puts "emitting c code for #{d.name}" if Rake.verbose == true
          if d.compiled and (not d.inline?) and (not d.primitive?)
            e.emit(d,c)
          end
          f << c
        rescue MFactor::CompileError => msg
          puts "WARNING: not emitting C code for #{d.name}: #{msg}"
        end
      end
    ensure
      f.flush
      f.close
    end
  end
end

# old
task :mfdeps do
  require 'tempfile'
  dotfile=Tempfile.new("_mfdeps_dot")
  dotfile << "digraph deps {\n"
  # files=FileList["lib/*.mfactor"]
  files = FileList["#{MFACTOR_SRC_DIR}/*.mfactor"]
  files.each do |f|
    puts "file: #{f}"
    cur=nil
    using=[]
    File.readlines(f).each do | line |
      if line =~ /IN:\s+(\S+)/
        cur=$1
      end
      if line =~ /USING:\s+((\S+\s+)+)/
        using = $1.split("\s")
      end
    end
    puts "IN: #{cur}\nUSING:#{using}"
    using.each do |used|
      dotfile << "#{cur} -> #{used}\n"
    end
  end
  dotfile << "}\n"
  dotfile.close
  cp dotfile.path, "mfdeps.dot"
  dotfile.unlink
end
