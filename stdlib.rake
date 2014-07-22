# -*- mode:ruby -*-

require 'yaml'

THISDIR=File.dirname(__FILE__)

# generate the mfactor side of the ff code
def ff_mfactor (yaml,out)
  i=0;
  out << <<END
USING: kernel ;
IN: ff
END
  yaml.each do |cname,opts|
    mfname= opts["name"]
    call = opts["call"] ? "ccall_"+opts["call"] : "" ; # if no call, then taken as literal (e.g. variable access)
    out << <<END
: #{mfname} ( -- ) #{i} ff #{call} ;
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
    out << "}\n;"
end

directory "generated"

require_relative "mfactor"
require_relative "mfactor_bytecode"

# main code generation routine

def build_stdlib
  puts "rebuilding stdlib from generated sources"
  if defined? $mfactor_ff
    ffyaml=YAML.load_file($mfactor_ff)
    ff_mfactor(ffyaml,File.open("generated/ff.mfactor","w"))
  end
  # iset=YAML.load_file("#{THISDIR}/instructionset.yml")
  # stdlib=YAML_Mfactor.new("generated/mfactor.yml",iset)
  mf=Object.const_get(GENERATOR).new
  mf.vocab_roots << MFACTOR_SRC_DIR
  mf.vocab_roots << "generated" # for ff code
  mf.load_vocab(MFACTOR_ROOT_VOCAB)
  File.open("generated/stdlib_size.h","w") do |f|
    f.puts "#define STDLIB_SIZE #{mf.bytecode_size}"
    # define the starting word for use in interpreter() call
    f.puts "#define START_WORD_OFFSET " + (mf.get_word_address(START_WORD)).to_s
  end
  File.open("generated/stdlib.code.h","w") do |f|
    ff_code(ffyaml || [],f)
    f.write "inst stdlib[#{mf.bytecode_size}]= {\n"
    mf.write_bytecode_image f
    f.write "};\n"
  end
  File.open("generated/stdlib.dict.h","w") do |f|
    f.write "dict_entry dict[VM_DICT] __attribute((aligned(1))) = {\n"
    mf.write_dictionary_entries f
    f.write "};\n"
  end
  mf
end

desc "show the mfactor dictionary"
task :see_dict => "generated" do
  puts build_stdlib.see
end

STDLIB_FILES=["generated/stdlib.code.h","generated/stdlib.dict.h","generated/stdlib_size.h"]
file "generated/_generated_" => STDLIB_FILES+["generated/inst_enum.h"] do
  touch "generated/_generated_"
end

STDLIB_FILES.each do |f|
  file f => ["generated","#{THISDIR}/instructionset.yml"]+FileList["#{THISDIR}/lib/*.mfactor"]+FileList["#{MFACTOR_SRC_DIR}/*.mfactor"] do
    build_stdlib
  end
  if defined? $mfactor_ff
    file f => $mfactor_ff
  end
end

file "generated/inst_enum.h" => ["#{THISDIR}/instructionset.yml"] do
  puts "updating instruction set"
  iset=YAML.load_file("#{THISDIR}/instructionset.yml")
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
task :stdlib => ["generated/stdlib.code.h","generated/stdlib.dict.h","generated/stdlib_size.h",__FILE__]

require 'pp'

task :mftest do
  mf=MF_Cortex.new
  mf.load_vocab("_stdlib")
  mf.see if Rake.verbose == true
#  mf.bytecode_image("top")
  mf.write_dictionary_entries STDOUT
  mf.write_inst_enum_entries STDOUT
  mf.write_bytecode_image STDOUT
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
