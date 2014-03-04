# -*- mode:ruby -*-
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
    # mnem is string
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
    # while start is the logical start in forward order, address
    # returns an actual target memory address
    def address
      CODEOFFSET+start # off by one
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
    structured=@thread_index.keys.map{|mft| mft.code}
    puts structured.inspect unless Rake.application.options.silent
    pass1=structured.flatten    
    j=0
    pass1.each do |value|
      if value.is_a?(Symbol)
        mft=@threads[value.to_s]
        puts "thread not found: #{value}" unless mft
        diff=mft.address-j
        out << " /*#{value}:0x#{diff.to_s(16)}*/"
        out << " 0x"+(((diff>>0))&0xff).to_s(16)+","
        out << " 0x"+(((diff>>8))&0xff).to_s(16)+","
        out << " 0x"+(((diff>>16))&0xff).to_s(16)+","
        out << " 0x"+(((diff>>24))&0xff).to_s(16)+","
        j += 4                  # jump length is platform dependent!!!
      else
        out << "0x"+value.to_s(16)+","
        j += 1
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
