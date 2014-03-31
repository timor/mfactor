# -*- mode:ruby -*-

require 'yaml'

# source: http://stackoverflow.com/questions/4692437/regex-with-named-capture-groups-getting-all-matches-in-ruby
class String
  # This method will return an array of MatchData's rather than the
  # array of strings returned by the vanilla `scan`.
  def match_all(regex)
    match_str = self
    match_datas = []
    while match_str.length > 0 do
      md = match_str.match(regex)
      break unless md
      match_datas << md
      match_str = md.post_match
    end
    return match_datas
  end
end


class YAML_Mfactor
  def self.dict_entry(address, name, prim=false)
    "{ .address = (inst *)#{prim ? " " : "&stdlib+"}0x#{address.to_s(16)}, .name = #{name.inspect}, .name_length=#{name.length + 1}},\n"
  end
  class ISet
    def initialize(yaml)
      @i_by_name={}
      @icodes={}
      j=INSTBASE
      yaml.each do |mnem,public_name|
        if (public_name != :private)
          @i_by_name[public_name || mnem.to_s]=mnem
        else
          if $noprivate
            @i_by_name[mnem.to_s] = mnem
          end
        end
        @icodes[mnem]=j
        j += 1
      end
    end
    # mnem is string
    def code(mnem)
      @icodes[mnem]
    end
    # print dictionary entry
    def dict(out)
      # puts @i_by_name unless Rake.application.options.silent
      @i_by_name.each do |name, mnem|
        out << YAML_Mfactor::dict_entry(@icodes[mnem] << (PTRSIZE-8),name,true)
      end
    end
  end
  class MFThread
    attr_accessor :instructions
    attr_accessor :name
    attr_accessor :start
    def initialize(name, instlist, iset, start)
      @instructions=instlist
      @name=name
      @instruction_set=iset
      @start=start
    end
    def code
      thread=[]
      @instructions.map do |i|
        if @instruction_set.code(i.to_s)
          thread.push("#{i}")
          thread.push(@instruction_set.code(i.to_s))
        else
          thread.push i
        end
      end
      thread.unshift("0x#{@start.to_s(16)}:#{@name}")
      thread
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
    $stdlib_size=codeptr
  end
  def length
    @thread_index.keys.map{|t| t.length}.reduce(:+)
  end
  # output a c array with the stdlib bytecode
  def code(out)
    structured=@thread_index.keys.map{|mft| mft.code}
    # puts structured.inspect unless Rake.application.options.silent
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
        raise "negative literals not supported right now" if value < 0
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

def maybe_tailcall(body)
  if body.length >= 1 && body[-1] == :scall
    body[-1] = :stcall
  elsif body.length >= 2 && body[-2] == :bcall
    body[-2] = :btcall
  end
end

def load_instructions(filename)
  iset={}
  IO.readlines(filename).each do |line|
    /^\s*(?<mnem>\w+):\s+("(?<name>\S+)")?/ =~ line
    if mnem
      iset[name||mnem] = mnem
    end
  end
  # puts iset,"\n"
  iset
end

def load_factor(filename,instructionset)
  # puts "reading instruction set from #{instructionset}"
  prims=load_instructions(instructionset)
  res={}
  text=File.read(filename).gsub(/!.*\n/,"") # remove comments here
  text.match_all(/(?<type>\S+)?:\s+(?<name>\S+)\s+(?<effect>\(.+\))\s+(?<words>.+);/).each do |match|
    name=match[:name]
    words=match[:words]
    type=match[:type]
    if match[:name]
      # puts "found word: #{name]}"
      puts "parsing word found: #{name}" if type == "SYNTAX"
      body=[]
      words.gsub!(/".+?"/) { |m| '::'+m.gsub(/\s/,'::SPACE::')+'::' }
      words.gsub!(/'(.)'/) { |m| $1.ord.to_s }
      words.gsub!("[","qstart")
      words.gsub!("]","qend")
      words.split("\s").each do |word|
        if prims[word]
          # possible proper tail call insertion
          if prims[word] == "qend"
            maybe_tailcall(body)
          end
          body.push prims[word].to_sym
        elsif /^\d+$/ =~ word
          body.push :litb
          body.push word.to_i
        elsif /^0[xX][[:xdigit:]]+$/ =~ word
          body.push :litb
          body.push word.hex
        elsif /::"(.+)"::/ =~ word
          body.push :strstart
          $1.gsub("::SPACE::"," ").chars.to_a.each { |s| body.push s.ord }
          body.push :strend
        else
          body.push :bcall
          body.push word.to_sym
        end
      end
      maybe_tailcall(body)
      body.push :qend
      res[name] = body
    end
  end
  res
end

THISDIR=File.dirname(__FILE__)
puts "looking for instruction set and stdlib code in #{THISDIR}"

file "generated/stdlib.yml" => ["#{THISDIR}/instructionset.yml","#{THISDIR}/stdlib.mfactor","#{THISDIR}/stdlib.rake","generated"] do
  File.open("generated/stdlib.yml","w") do |f|
    code=load_factor("#{THISDIR}/stdlib.mfactor","#{THISDIR}/instructionset.yml")
    # puts code
    f.write(code.to_yaml)
  end
end

directory "generated"
task :stdlib => ["#{THISDIR}/instructionset.yml","generated/stdlib.yml","generated"] do
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
  stdlib=YAML_Mfactor.new("generated/stdlib.yml",iset)
  File.open("generated/stdlib_size.h","w") do |f|
    f.puts "#define STDLIB_SIZE #{$stdlib_size}"
  end
  File.open("generated/stdlib.code.h","w") do |f|
    f.write "inst stdlib[#{$stdlib_size}]= {\n"
    stdlib.code(f)
    f.write "};\n"
  end
  File.open("generated/stdlib.dict.h","w") do |f|
    f.write "dict_entry dict[VM_DICT] __attribute((aligned(1))) = {\n"
    stdlib.dict(f)
    f.write "};\n"
  end
end
