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
CODEOFFSET=0
if hostp
  INSTBASE=0x80
  CC="gcc"
  GDB="gdb"
  LDFLAGS << "-Wl,-Map=#{MAP}"
  PTRSIZE=64
else
  INSTBASE=0xa0
  PTRSIZE=32
  # CODEMEM=0x2000ef6c
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

import "stdlib.rake"

task :inst => :stdlib

file "interpreter.o" => :inst
