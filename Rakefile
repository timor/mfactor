# -*- mode:ruby -*-
require 'rake/clean'
require 'tempfile'

hostp=ENV['ONHOST']
$noprivate=ENV['NOPRIVATE'] && ( ENV['NOPRIVATE'] != '0' )
notailcall=ENV['NOTAILCALL']

PROG=hostp ? "mfactor" : "mfactor.elf"
MAP=PROG.ext('.map')
CLEAN.include MAP
OPT="0"
CFLAGS= "-O#{OPT} -std=gnu99 -g "
LDFLAGS= "-O#{OPT} -std=gnu99 -g "
LDSCRIPT="gcc.ld"
CODEOFFSET=0
trace_level=ENV['TRACE_LEVEL'] || 0
CFLAGS << " -DTRACE_INTERPRETER=#{trace_level}"
CFLAGS << " -DDEBUG=#{ENV['DEBUG']}" if ENV['DEBUG']
START_WORD="top"
if hostp
  INSTBASE=0x80
  CC="gcc"
  GDB="gdb"
  LDFLAGS << "-lrt -Wl,-Map=#{MAP}"
  PTRSIZE=64
  SIZE="size"
  CFLAGS << " -DVM_RETURNSTACK=256 "
  GENERATOR='MF_Linux64'
else
  INSTBASE=0xa0
  PTRSIZE=32
  # CODEMEM=0x2000ef6c
  LDFLAGS << " -Wl,-Map=#{MAP} --specs=nano.specs -lc -lnosys -flto -Wl,--gc-sections -Wl,--cref -nostartfiles -mcpu=cortex-m3 -mthumb"
  LDFLAGS << " -v" if ENV['VERBOSE']
  CFLAGS << " -ffunction-sections -fdata-sections"
  CFLAGS << " -mcpu=cortex-m3 -D__START=main -mthumb"
  CFLAGS << " -v" if ENV['VERBOSE']
  CFLAGS << " -DCORTEX_M"
  CC="arm-none-eabi-gcc"
  GDB="arm-none-eabi-gdb"
  OBJDUMP="arm-none-eabi-objdump"
  SIZE="arm-none-eabi-size"
  GENERATOR='MF_Cortex'
end

# include
CFLAGS << " -I. "
  
hfiles = FileList['*.h']
cfiles=FileList['*.[cCsS]']
if hostp
  cfiles += FileList["target/linux/*.[cCsS]"]
else
  cfiles += FileList["target/cortex/*.[cCsS]"]
end
cfiles.each do |c|
  file c.ext('o') => c
end
ofiles=cfiles.ext('.o')
CLEAN.include ofiles

BUILD="build"
directory BUILD

rule '.o' => '.c' do |t|
  cflags=CFLAGS
  cflags += " -DNOTAILCALL" if notailcall != "0"
  cflags += " -DSTOP_ON_ERROR" if ENV['STOP_ON_ERROR']
  tname = t.source.pathmap("#{BUILD}/%n.i")
  sh "#{CC} #{cflags} #{t.source} -E -o #{tname}"
  sh "#{CC} #{cflags} #{t.source} -c -o #{t.name}"
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

task :size => [PROG] do
  sh "#{SIZE} #{PROG}" unless Rake.application.options.silent
end

task :default => [PROG,:size]

if hostp
  task :run => PROG do
    sh "./#{PROG}"
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

# $mfactor_sources=FileList["lib/*.mfactor"]
MFACTOR_SRC_DIR=""
MFACTOR_ROOT_VOCAB="tests"

require 'yaml'

CLEAN.include "generated"

file "interpreter.o" => [:stdlib,"generated/inst_enum.h"]
