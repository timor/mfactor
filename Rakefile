# -*- mode:ruby -*-
require 'rake/clean'

hostp=ENV['ONHOST']

PROG=hostp ? "mfactor" : "mfactor.elf"
MAP=PROG.ext('.map')
CLEAN.include MAP
OPT="0"
CFLAGS= "-O#{OPT} -std=gnu99 -g "
LDFLAGS= "-O#{OPT} -std=gnu99 -g "
LDSCRIPT="gcc.ld"
if hostp
  CC="gcc"
  GDB="gdb"
  LDFLAGS << "-Wl,-Map=#{MAP}"
else
  LDFLAGS << " -Wl,-Map=#{MAP} --specs=nano.specs -lc -lnosys -flto -fwhole-program -ffunction-sections -fdata-sections -Wl,--gc-sections -Wl,--cref -nostartfiles -mcpu=cortex-m3 -mthumb"
  LDFLAGS << " -v" if ENV['VERBOSE']
  CFLAGS << " -mcpu=cortex-m3 -D__START=main -mthumb"
  CFLAGS << " -v" if ENV['VERBOSE']
  CC="arm-none-eabi-gcc"
  GDB="arm-none-eabi-gdb"
  OBJDUMP="arm-none-eabi-objdump"
  SIZE="arm-none-eabi-size"
end
  
cfiles=FileList['*.[cCsS]'].each do |c|
  file c.ext('o') => c
end
unless hostp
  cfiles += FileList["target/*.[cCsS]"]
end
ofiles=cfiles.ext('.o')
CLEAN.include ofiles

rule '.o' => '.c' do |t|
  sh "#{CC} #{CFLAGS} #{t.source} -c -o #{t.name}"
end

rule '.o' => '.S' do |t|
  sh "#{CC} #{CFLAGS} #{t.source} -c -o #{t.name}"
end

ofiles.each{|o| file o => "Rakefile"}

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
  sh "qemu-system-arm -cpu cortex-m3 -kernel #{PROG} -gdb tcp::1234 -M lm3s6965evb -serial stdio -nographic -monitor null"
end

CLEAN.include PROG.ext('lst')

task :debug => PROG do
  args = ""
  if ENV['INSIDE_EMACS']
    args += " -i=mi"
  else
    args += " --tui"
  end
  sh "#{GDB} #{args} #{PROG}"
end
