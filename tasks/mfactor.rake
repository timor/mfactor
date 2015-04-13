# -*- mode:ruby -*-

require 'yaml'
require 'tempfile'
# set up load path
$:.unshift(File.join(File.dirname(__FILE__),"..","lib"))
require_relative '../lib/mfactor/analyze'

THISDIR=File.dirname(__FILE__)
ISETFILE=File.join(THISDIR,"../instructionset.yml")
# make target application's object file depend on the generated stuff
MFACTOR_DEPENDING_OBJECT ||= "mfactor/src/interpreter.c"
# can be a hash table that contains pairs of the form (mfactor-word -> name-of-c-define)
MFACTOR_C_WORDS ||= {}
puts "no c translations" if MFACTOR_C_WORDS == {}
INSTBASE=
  if GENERATOR == "Cortex"
    0xa0
  elsif GENERATOR == "Linux64"
    0x80
  end

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
  File.open("generated/image_size.h","w") do |f|
    f.puts "#define IMAGE_SIZE #{mf.bytecode_size}"
    # define the starting word for use in interpreter() call
    f.puts "#define START_WORD_OFFSET " + (mf.get_word_address(START_WORD)).to_s
  end
  File.open("generated/image.code.h","w") do |f|
    ff_code(ffyaml || [],f)
    f.write "inst image[#{mf.bytecode_size}]= {\n"
    mf.write_bytecode_image f
    f.write "};\n"
  end
  File.open("generated/image.dict.h","w") do |f|
    f.write "dict_entry dict[VM_DICT] __attribute((aligned(1))) = {\n"
    mf.write_dictionary_entries f
    f.write "};\n"
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
    build_image
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

# iterate through all vocabularies
# generate a subdir in generated for each vocabulary, generate a control flow graphic for each word, if applicable
task :compile_all => "generated/cfg" do
  $stdout.sync=true
  if defined? MFACTOR_FF
    ffyaml=YAML.load_file(MFACTOR_FF)
    ff_mfactor(ffyaml,File.open("generated/ff.mfactor","w"))
  end
  mf=MFactor::Image.new([MFACTOR_SRC_DIR,"generated"])
  mf.load_vocab(MFACTOR_ROOT_VOCAB)
  a=MFactor::MFStaticCompiler.new(mf)
  mf.dictionary.each do |name,vocab|
    dir="generated/cfg/#{name}"
    mkdir_p dir
    vocab.definitions.each do |d|
      next unless d.compilable?
      begin
        dotfname=dir+"/#{MFactor::filename_escape(d.name)}.dot"
        dotfile= File.new(dotfname,"w")
        a.definition_dot_graph d, dotfile
        dotfile.close
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
        puts "Compilation Log:"
        puts d.compile_log
        raise
      ensure
        sh "dot -Tpng #{dotfname} -o #{dotfname.ext('png')} " if File.exist?(dotfname)
        File.open(dotfname.ext('log'),"w") do |f|
          f.puts d.compile_log
        end

      end
    end
  end
end

task :mfdeps do
  require 'tempfile'
  dotfile=Tempfile.new("_mfdeps_dot")
  dotfile << "digraph deps {\n"
  files=FileList["lib/*.mfactor"]
  files.each do |f|
    puts "file: #{f}"
    cur=nil
    using=[]
    File.readlines(f).each do | line |
      if line =~ /IN:\s+(\w+)/
        cur=$1
      end
      if line =~ /USING:\s+((\w+\s+)+)/
        using = $1.split("\s")
      end
    end
    puts "IN: #{cur}\nUSING:#{using}"
    using.each do |used|
      dotfile << "#{used} -> #{cur}\n"
    end
  end
  dotfile << "}\n"
  dotfile.close
  cp dotfile.path, "mfdeps.dot"
  dotfile.unlink
end