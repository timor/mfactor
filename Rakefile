# -*- mode:ruby -*-
require 'rake/clean'
require 'tempfile'

hostp=ENV['ONHOST']

PROG=hostp ? "mfactor" : "mfactor.elf"
MAP=PROG.ext('.map')
CLEAN.include MAP
OPT="0"
CFLAGS= "-O#{OPT} -std=gnu99 -g "
LDFLAGS= "-O#{OPT} -std=gnu99 -g "
LDSCRIPT="gcc.ld"
if hostp
  INSTBASE=0x80
  CC="gcc"
  GDB="gdb"
  LDFLAGS << "-Wl,-Map=#{MAP}"
else
  INSTBASE=0xa0
  LDFLAGS << " -Wl,-Map=#{MAP} --specs=nano.specs -lc -lnosys -flto -Wl,--gc-sections -Wl,--cref -nostartfiles -mcpu=cortex-m3 -mthumb"
  LDFLAGS << " -v" if ENV['VERBOSE']
  CFLAGS << " -ffunction-sections -fdata-sections"
  CFLAGS << " -mcpu=cortex-m3 -D__START=main -mthumb"
  CFLAGS << " -v" if ENV['VERBOSE']
  CFLAGS << " -DCPU_LPC4337"
  CFLAGS << " -DTRACE_INTERPRETER=0"
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
    sh "#{SIZE} #{PROG}"
  end
end
CLOBBER.include PROG

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

directory "generated"
task :iset => ["instructionset.yml","generated"] do
  require 'yaml'
  YAML::ENGINE.yamler = 'syck'
  @iset=YAML.load_file("instructionset.yml")
  File.open("generated/inst_enum.h","w") do |f|
    f.puts "enum inst_set {\n"
    i=INSTBASE
    @iset.each do |mnem,name| 
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

def ymlforth(infile)
  Rake::Task["iset"].invoke
  def getinst(n)
    case n
    when Symbol
      i=@iset.keys.index(n.to_s)
      # i ? (INSTBASE+i) : "CALL(#{n.to_s})"
      i ? n : "CALL(#{n.to_s})"
    when String
      n.inspect
    else
      puts "unknown word or literal: #{n}"
    end
  end
  require 'yaml'
  lib=YAML.load_file(infile.ext("yml"))
  File.open(("generated/"+File.basename(infile,".*")+".code.x").ext("h"),"w") do |f|
    lib.each do |name, thread|
      f.write "inst #{name}[] {"
      f.write(thread.reverse.push(:retsub).map{|word| getinst(word)}.join(", "))
      f.write("};\n\n")
    end
  end
  File.open(("generated/"+File.basename(infile,".*")+".dict.x").ext("h"),"w") do |f|
    lib.each do |name, thread|
      f.puts("TDICT(#{name.inspect},#{name}),\n")
    end
  end
end

task :inst do
  ymlforth("stdlib.yml")
end


file "interpreter.o" => :inst
