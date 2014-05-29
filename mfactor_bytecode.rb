# the code that actually emits something from a already parsed mfactor file set
# performs dictionary validation among other stuff


require_relative 'mfactor'


# expect to be created with already loaded MFactor instance
class MF_ByteCode < MFactor
  SEQ_ELT_CELL=0
  SEQ_FIXED=1
  SEQ_QUOT=2
  SEQ_USER=3
  SEQ_BYTE_COND=4
  def initialize(*args)
    super
    @locations={}                 # stores memory locations of definitions
    @prims={}                     # set of primitives for this architecture
    ISET.each_with_index do |elt,i|
      @prims[elt[0]]=inst_base+i
    end
    @definition_code={}               # holds the actual byte code
  end
  # some architecture-specific definitions
  def atom_size(elt)
    raise "overwrite atom_size in sub-class"
  end
  def inst_base()
    raise "overwrite inst_base in subclass"
  end
  def bcall_bytes(val)
    [val].pack("I").unpack("CC")
  end
  # actual code generation routine
  def bytecode_image(start_word)
    raise "unknown entry point: '#{start_word}'" unless find_name(start_word)
    image=[]
    memloc=0
    def_list=@dictionary.values.map{|v| v.definitions}.flatten
    def_list.each do |d|
      code=[]
      @locations[d]=memloc
      defsize=0
      puts "compiling definition for #{d.name}" if Rake.verbose == true
      d.body.each do |word|
        defsize += element_size(word)
        word_bytecode(word,code)
      end
      code << prim(:qend)      # maybe omit, check space savings
      puts "#{d.name} is at #{memloc}" if Rake.verbose == true
      memloc += defsize+1
      @definition_code[d]=code
    end
    puts "total bytecode size: #{memloc}" if Rake.verbose
    @locations.each do |d,loc|
      puts "@#{loc}: #{d.name} "
      print @definition_code[d]
      puts ";"
    end if Rake.verbose == true
    print ISET.keys.map{ |name| [name,prim(name)] },"\n" if Rake.verbose == true
    check_locations
    @definition_code.values.flatten
  end
  # check pre-compile size computations
  def check_locations
    loc=0
    @definition_code.each do |d,code|
      if loc != @locations[d]
        raise "unmatched location for #{d.name}: counted #{loc}, expected #{@locations[d]}!"
      end
      loc += code.length
    end
    raise "internal indices don't match" unless @definition_code.keys == @locations.keys
  end
  # element size
  def element_size(elt)
    case elt
    when String then header_length + elt.chars.to_a.length
    when Array then 2 + elt.map{|e| element_size(e)}.reduce(:+)
    when MFLitSequence then header_length + elt.content.map{|e| element_size(e)}.reduce(:+)
    else atom_size(elt)
    end
  end
  def inline_seq_header(elt_type, elt_size, count, image)
    raise "inline sequences longer than 255 elements not supported!" if count >= 256
    image << prim(:litc) << ((SEQ_FIXED << 5) | (elt_type << 2) | elt_size) << count 
  end
  # generate byte code for one word, append to image
  def word_bytecode(word,image)
    case word
    when String then
      inline_seq_header(0,1,word.chars.to_a.length,image)
      image.concat word.chars.map{|c| c.ord}
    when Array then
      image << prim(:qstart)
      word.map{|w| word_bytecode(w,image)}
      image << prim(:qend)      # maybe omit, check space savings
    when MFLitSequence then
      inline_seq_header(0,word.element_size,word.content.length,image)
      word.content.map{|w| word_bytecode(w,image)}
    when MFByteLit then image << prim(:litb) << word.value
    when MFIntLit then (image << prim(:liti)).concat int_bytes(value)
    when MFPrim then image << prim(word.name)
    when MFWord then
      # puts "referring to #{word.name}"
      image << ( word.is_tail ? prim(:btcall) : prim(:bcall) )
      image.concat bcall_bytes(@locations[word.definition])
    else raise "don't know how to compile #{word}"
    end
  end
  def prim(name)
    @prims[name.to_s]
  end
end

class MF_Cortex < MF_ByteCode
  def atom_size(elt)
    @sizes={
      MFPrim => 1,
      MFWord => 3,
      MFByteLit => 2,
      MFIntLit => 5 }
    s=@sizes[elt.class]
    raise "unknown element size: #{elt} of #{elt.class}" unless s
    s
  end
  def inst_base() 0xa0 end
  def header_length() 3 end
  def int_bytes(val)
    [val].pack("I").unpack("CCCC")
  end
end

class MF_Linux64 < MF_ByteCode
  def atom_size
    @sizes={
      MFPrim => 1,
      MFWord => 3,
      MFByteLit => 2,
      MFIntLit => 9 }
    s=@sizes[elt.class]
    raise "unknown element size: #{elt} of #{elt.class}" unless s
    s
  end
  def inst_base() 0x70 end
  def header_length() 3 end
  def int_bytes(val)
    [val].pack("I").unpack("CCCCCCCC")
  end
end
