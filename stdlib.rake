# -*- mode:ruby -*-
class YAML_Mfactor
  def self.dict_entry(address, name, prim=false)
    "{ .address = (void *)#{prim ? " " : "&stdlib+"}0x#{address.to_s(16)}, .name = #{name.inspect}, .name_length=#{name.length + 1}},\n"
  end
  class ISet
    def initialize(yaml)
      @i_by_name={}
      @icodes={}
      j=INSTBASE
      yaml.each do |mnem,public_name|
        if public_name != :private
          @i_by_name[public_name || mnem.to_s]=mnem
        end
        @icodes[mnem]=j
        j += 1
      end
    end
    # mnem is string
    def code(mnem)
      @icodes[mnem]
    end
    def dict(out)
      puts @i_by_name unless Rake.application.options.silent
      @i_by_name.each do |name, mnem|
        out << YAML_Mfactor::dict_entry(@icodes[mnem] << 24,name,true)
      end
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
      end.unshift("0x#{@start.to_s(16)}:#{@name}")
    end
    def length
      sum=0
      # short jumps are two bytes long, other jumps not
      # supported in generated code
      code().each do |i|
        sum += case i
               when Integer then 1
               when Symbol then 2
               else 0
               end
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
  # output a c array with the stdlib bytecode
  def code(out)
    structured=@thread_index.keys.map{|mft| mft.code}
    puts structured.inspect unless Rake.application.options.silent
    pass1=structured.flatten    
    j=0
    pass1.each do |value|
      if value.is_a?(Symbol)
        mft=@threads[value.to_s]
        puts "thread not found: #{value}" unless mft
        diff=mft.address
        out << " /*0x#{j.to_s(16)}:->#{value}:0x#{diff.to_s(16)}*/"
        out << " 0x"+(((diff>>0))&0xff).to_s(16)+","
        out << " 0x"+(((diff>>8))&0xff).to_s(16)+","
        # out << " 0x"+(((diff>>16))&0xff).to_s(16)+","
        # out << " 0x"+(((diff>>24))&0xff).to_s(16)+","
        j += 2                  # jump length is platform dependent!!!
      elsif value.is_a?(String)
        out << "/*#{value}*/ "
      else
        out << "0x"+value.to_s(16)+","
        j += 1
      end
    end
    nil
  end
  # output dict for stdlib
  def dict(out)
    @instruction_set.dict(out)
    @thread_index.keys.each do |mft|
      out << self.class.dict_entry(mft.start, mft.name)
    end
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
  File.open(("generated/stdlib.dict.h"),"w") do |f|
    f.write "dict_entry dict[VM_DICT] __attribute((aligned(1))) = {\n"
    stdlib.dict(f)
    f.write "};\n"
  end
end
