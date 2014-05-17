# the code that actually emits something from a already parsed mfactor file set
# performs dictionary validation among other stuff


require_relative 'mfactor'


# expect to be created with already loaded MFactor instance
class MFEmitter
  def initialize(mf)
    @mf=mf                      # MFactor instance
    @locations={}                 # stores beginnings of words
    @prims={}
    ISET.each_with_index do |elt,i|
      @prims[elt]=inst_base()+i
    end
  end
  # compute the size of one element
  def inst_base() raise "subclass inst_base!" end
  def atom_size(elt) raise "subclass definition_size!" end
  def header_length() raise "subclass header_length!" end
  def bcall_bytes() raise "subclass bcall_bytes!" end
  def int_bytes() raise "subclass int_bytes!" end
  def inst_base() raise "subclass inst_base!" end
  # make sure everything is defined and reachable
  def walk_dict(dict,memloc)
    puts "collecting locations of vocab '#{dict.name}'"
    dict.definitions.each do |d|
      defsize=0
      STDOUT.flush
      d.body.each do |word|
        defsize += element_size(word)
      end
      @locations[d]=memloc
      puts "#{d.name} is at #{memloc}"
      memloc += defsize
    end
    memloc
  end
  def walk_all_dicts
    mem=0
    @mf.dictionary.values.each do |dict|
      mem = walk_dict(dict,mem)
    end
    puts "total bytecode image size: #{mem}"
  end
  # element size
  def element_size(elt)
    case elt
      when String then header_length() + elt.chars.length
      when Array then 2*atom_size(MFPrim.new) + elt.map{|e| element_size(e)}.reduce(:+)
      when MFLitSequence then header_length() + elt.content.map{|e| element_size(e)}.reduce(:+)
      else atom_size(elt)
    end
  end
  # generate byte code for one word, append to image
  def bytecode(word,image)
    puts "generating bcode for #{word}"
    case word
    when String then
      image << prim(:bastart)
      image += word.chars.map(:ord)
    when Array then
      image << prim(:qstart)
      image += word.map{|w| bytecode(w,image)}
      # TODO: adjust tail calls here!
      image << prim(:qend)      # maybe omit, check space savings
    when MFLitSequence then
      image << prim(:bastart)
      image += word.contents.map{|w| bytecode(w,image)}
    when MFByteLit then image << word.value
    when MFIntLit then image += int_bytes(value)
    when MFPrim then image << prim(word.name)
    when MFWord then image += bcall_bytes(@locations[word.definition])
    else raise "don't know how to compile #{word}"
    end
  end
  # generate bytecode
  def bytecode_image()
    # TODO: include remove unused pass (mark don't sweep)!
    image=[]
    walk_all_dicts
    @mf.dictionary.values.each do |dict|
      dict.definitions.each do |d|
        puts "compiling definition for #{d.name}"
        d.body.each do |word|
          bytecode(word,image)
        end
      end
    end
  end
  def prim(name)
    @prims[name.to_s]
  end
end

class MFEmitter_Cortex < MFEmitter
  def initialize(mf)
    super
    @sizes={
      MFPrim => 1,
      MFWord => 3,
      MFByteLit => 1,
      MFIntLit => 5 }
  end
  def atom_size(elt)
    s=@sizes[elt.class]
    raise "unknown element size: #{elt} of #{elt.class}" unless s
    s
  end
  def header_length() 3 end
  def int_bytes(val)
    [val].pack("I").unpack("CCCC")
  end
  def bcall_bytes(val)
    [val].pack("I").unpack("CC")
  end
  def inst_base() 0x70 end
end
