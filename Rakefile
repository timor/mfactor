# -*- mode:ruby -*-
require 'rake/clean'
require 'tempfile'

hostp=ENV['ONHOST']

PROG=hostp ? "mfactor" : "mfactor.elf"
MAP=PROG.ext('.map')
CLEAN.include MAP
OPT="0"
STDLIB_SIZE=256;
CFLAGS= "-O#{OPT} -std=gnu99 -g -DSTDLIB_SIZE=#{STDLIB_SIZE}"
LDFLAGS= "-O#{OPT} -std=gnu99 -g "
LDSCRIPT="gcc.ld"
if hostp
  INSTBASE=0x80
  CC="gcc"
  GDB="gdb"
  LDFLAGS << "-Wl,-Map=#{MAP}"
else
  INSTBASE=0xa0
  CODEMEM=0x2000ef6c
  LDFLAGS << " -Wl,-Map=#{MAP} --specs=nano.specs -lc -lnosys -flto -Wl,--gc-sections -Wl,--cref -nostartfiles -mcpu=cortex-m3 -mthumb"
  LDFLAGS << " -v" if ENV['VERBOSE']
  CFLAGS << " -ffunction-sections -fdata-sections"
  CFLAGS << " -mcpu=cortex-m3 -D__START=main -mthumb"
  CFLAGS << " -v" if ENV['VERBOSE']
  CFLAGS << " -DCPU_LPC4337"
  CFLAGS << " -DTRACE_INTERPRETER=2"
  CC="arm-none-eabi-gcc"
  GDB="arm-none-eabi-gdb"
  OBJDUMP="arm-none-eabi-objdump"
  SIZE="arm-none-eabi-size"
end
  
hfiles = FileList['*.h']
cfiles=FileList['*.[cCsS]']
unless hostp
  cfiles += FileList["target/*.[cCsS]"]
end
cfiles.each do |c|
  file c.ext('o') => c
end
ofiles=cfiles.ext('.o')
CLEAN.include ofiles

BUILD="build"
directory BUILD

rule '.o' => '.c' do |t|
  tname = t.source.pathmap("#{BUILD}/%n.i")
  sh "#{CC} #{CFLAGS} #{t.source} -E -o #{tname}"
  sh "#{CC} #{CFLAGS} #{t.source} -c -o #{t.name}"
end

rule '.o' => '.S' do |t|
  sh "#{CC} #{CFLAGS} #{t.source} -c -o #{t.name}"
end

ofiles.each{|o| file o => ["Rakefile",BUILD]+hfiles}

unless hostp
  file PROG => [LDSCRIPT]
  LDFLAGS << " -T #{LDSCRIPT}"
end
file PROG => ofiles
file PROG do
  sh "#{CC} #{LDFLAGS} #{ofiles} -o #{PROG}"
  unless hostp
    sh "#{OBJDUMP} -dS #{PROG} > #{PROG.ext('lst')}"
  end
end
CLOBBER.include PROG

task :size do
  sh "#{SIZE} #{PROG}"
end

task :default => PROG

if hostp
  task :run => PROG do
    sh PROG
  end
end

task :sim => PROG do 
  sh "qemu-system-arm -cpu cortex-m3 -kernel #{PROG} -gdb tcp::1234 -M lm3s6965evb -serial pty -nographic"
end

CLEAN.include PROG.ext('lst')

task :debug => PROG do
  script=Tempfile.new("gdbscript");
  script << <<GDBEND
define reset
  monitor reset
  load
end
define connect
  target remote :1234
end
connect
reset
GDBEND
  script.close
  args = ""
  if ENV['INSIDE_EMACS']
    args += " -i=mi"
  else
    args += " --tui"
  end
  args += " -x #{script.path}"
  sh "#{GDB} #{args} #{PROG}"
end

class YAML_Mfactor
  class ISet
    def initialize(yaml)
      @i_by_name={}
      @icodes={}
      j=INSTBASE
      yaml.each do |mnem,public_name|
        if public_name != :private
          @i_by_name[public_name]=mnem
        end
        @icodes[mnem]=j
        j += 1
      end
    end
    def code(mnem)
      @icodes[mnem]
    end
  end
  class MFThread
    attr_accessor :instructions
    attr_accessor :name
    attr_accessor :start
    def initialize(name, instlist, iset, start)
      @instructions=instlist+[:qend]
      @name=name
      @instruction_set=iset
      @start=start
    end
    def code
      @instructions.map do |i|
        @instruction_set.code(i.to_s) ? @instruction_set.code(i.to_s) :
          (i.is_a?(String) ? i.ord : i)
      end
    end
    def length
      sum=0
      code().each do |i|
        sum += (i.is_a?(Integer) ? 1 : 4) # platform dependent (ptrdiff)!!!
      end
      sum
    end
    # whiel start is the logical start in forward order, address
    # returns an actual target memory address
    def address
      CODEMEM+STDLIB_SIZE-start-1 # off by one
    end
  end
  
  def initialize(ymlfile,isetyaml)
    @yaml=YAML.load_file(ymlfile)
    @thread_index={}
    @threads={}
    @instruction_set=ISet.new(isetyaml)
    codeptr=0
    @yaml.each do |name, thread|
      mft=MFThread.new(name,thread,@instruction_set,codeptr);
      @threads[name]=mft;
      @thread_index[mft]=codeptr;
      codeptr += mft.length;
    end
  end
  def length
    @thread_index.keys.map{|t| t.length}.reduce(:+)
  end
  def code(out)
    padding=STDLIB_SIZE-length()
    puts "code exceeding stdlib size" unless padding >= 0
    padding.times { out << " 0," }
    pass1=@thread_index.keys.map{|mft| mft.code}.flatten.reverse    
    # puts pass1.inspect
    # j=0
    pass1.each do |value|
      if value.is_a?(Symbol)
        mft=@threads[value.to_s]
        puts "thread not found: #{value}" unless mft
        jump=mft.address;
        out << " /*#{value}:0x#{jump.to_s(16)}*/"
        out << " 0x"+(((jump>>0))&0xff).to_s(16)+","
        out << " 0x"+(((jump>>8))&0xff).to_s(16)+","
        out << " 0x"+(((jump>>16))&0xff).to_s(16)+","
        out << " 0x"+(((jump>>24))&0xff).to_s(16)+","
        # j += 4
      else
        out << "0x"+value.to_s(16)+","
        # j += 1
      end
    end
    nil
  end
end

directory "generated"
task :stdlib => ["instructionset.yml","stdlib.yml","generated"] do
  require 'yaml'
  YAML::ENGINE.yamler = 'syck'
  iset=YAML.load_file("instructionset.yml")
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
  stdlib=YAML_Mfactor.new("stdlib.yml",iset)
  File.open(("generated/stdlib.code.h"),"w") do |f|
    f.write "inst stdlib[#{STDLIB_SIZE}]= {\n"
    stdlib.code(f)
    f.write "};\n"
  end
end

task :inst => :stdlib

file "interpreter.o" => :inst
