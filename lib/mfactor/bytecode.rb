# the code that actually emits something from a already parsed mfactor file set
# performs dictionary validation among other stuff


require 'mfactor/image'

module MFactor

  # holds specialized compiled information
  class MFCompiledDefinition < Struct.new(:definition,:location,:code,:flags)
    def write_dict_entry(bytecode,io="")
      loc = definition.primitive? ? "0x#{(location << (8*(bytecode.cell_width-1))).to_s(16)}" : "&stdlib+#{location.to_s}"
      io <<
        "{ .address = (inst *)#{loc}, .flags = #{flags}, .name = #{definition.name.to_s.inspect}, .name_length=#{definition.name.to_s.length + 1}}"
    end
  end


  # expect to be created with already loaded MFactor instance
  class ByteCodeImage < Image
    SEQ_ELT_DATA=0
    SEQ_ELT_REF=1
    attr_accessor :compiled_definitions
    def initialize(*a)
      super *a
      @prims={}                     # set of primitives for this architecture
      @compiled_definitions=[]               # holds the actual byte code
      ISET.each_with_index do |elt,i|
        @prims[elt[0]]=inst_base+i
        # create pseudo-definitions for primitives
        # TODO: actually use the provided definitions
        @compiled_definitions << MFCompiledDefinition.new(MFDefinition.new(elt[0],"PRIM:",nil,[]),inst_base+i,[],2)
      end
      @generated                    # flag for on-demand bytecode generation
      @size                         # store bytecode size here after generation
    end
    # some architecture-specific definitions
    def cell_width(elt)
      raise "overwrite cell_width in sub-class"
    end
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
    def maybe_generate
      return if @generated
      puts "\nGenerating byte_code image" if Rake.verbose
      image=[]
      memloc=0
      def_list=@dictionary.values.map{|v| v.definitions}.flatten.reject{|d| d.primitive?}
      def_list.each do |d|
        code=[]
        cdef=MFCompiledDefinition.new
        cdef.location=memloc
        cdef.definition=d
        cdef.flags=(cdef.definition.definer == "SYNTAX:" ? 1 : 0)
        @compiled_definitions << cdef # adding here already although body may be empty
        defsize=0
        puts "compiling definition for #{d.name}" if Rake.verbose == true
        d.body.each do |word|
          defsize += element_size(word)
          word_bytecode(word,code)
        end
        code << prim(:qend)      # maybe omit, check space savings
        puts "#{d.name} is at #{memloc}" if Rake.verbose == true
        memloc += defsize+1
        cdef.code=code
      end
      @size=memloc
      puts "total bytecode size: #{memloc}" if Rake.verbose
      puts "memory map:" if Rake.verbose
      @compiled_definitions.each do |d|
        puts "@#{d.location}: #{d.definition.name} #{d.definition.primitive? ? 'prim' : '' }"
        print d.code
        puts ";" if d.code
      end if Rake.verbose == true
      print ISET.keys.map{ |name| [name,prim(name)] },"\n" if Rake.verbose == true
      check_locations
      @generated = true
      #@compiled_definitions.map{|d| d.code}.flatten
    end
    # check pre-compile size computations
    def check_locations
      loc=0
      @compiled_definitions.each do |d|
        puts "double-checking compiled location of #{d.definition.name}" if Rake.verbose == true
        if d.definition.primitive?
          puts "skipping primitive" if Rake.verbose == true
          next
        end
        if loc != d.location
          raise "unmatched location for '#{d.definition.name}': counted #{loc}, expected #{d.location}!"
        end
        loc += d.code.length
      end
    end
    # element size
    def element_size(elt)
      case elt
      when String then header_length + elt.chars.to_a.length
      when Array then 2 + elt.map{|e| element_size(e)}.reduce(:+)
      when MFLitSequence then header_length + elt.element_size * elt.content.length
      else atom_size(elt)
      end
    end
    def inline_seq_header(elt_type, elt_size, count, image)
      raise "inline sequences longer than 255 elements not supported!" if count >= 256
      size_indicator=Rational(Math::log2(elt_size))
      raise "element size not a power of 2: #{elt_size}" if size_indicator.denominator != 1
      image << prim(:litc) << (0 | (elt_type << 3) | size_indicator.numerator) << count
    end
    # generate byte code for one word, append to image
    def word_bytecode(word,image)
      case word
      when String then
        inline_seq_header(SEQ_ELT_DATA,1,word.chars.to_a.length,image)
        image.concat word.chars.map{|c| c.ord}
      when Array then
        image << prim(:qstart)
        word.map{|w| word_bytecode(w,image)}
        image << prim(:qend)      # maybe omit, check space savings
      when MFLitSequence then
        inline_seq_header(SEQ_ELT_DATA,word.element_size,word.content.length,image)
        word.content.map{|w| image.concat int_bytes(w.value,word.element_size)}
      when MFByteLit then image << prim(:litb) << word.value
      when MFIntLit then (image << prim(:liti)).concat int_bytes(word.value,cell_width)
      when MFWord then
        if word.definition.primitive?
          if word.is_tail && word.name == "call"
            image << prim("stcall")
          else
            image << prim(word.name)
          end
        else
          # puts "referring to #{word.name}"
          image << ( word.is_tail ? prim(:btcall) : prim(:bcall) )
          image.concat bcall_bytes(@compiled_definitions.find{|cdef| cdef.definition==word.definition}.location)
        end
      else raise "don't know how to compile #{word}"
      end
    end
    def prim?(name)
      @prims[name.to_s]
    end
    def prim(name)
      @prims[name.to_s] || raise( "unknown primitive: #{name}")
    end
    # c code generation:
    # c99 initiailizers for the dictionary
    def write_dictionary_entries(io="")
      maybe_generate
      @compiled_definitions.each do |cdef|
        if cdef.definition.name.to_s =~ /^_.*/
          puts "skipping private word: #{cdef.definition.name} " if Rake.verbose == true
        else
          io << cdef.write_dict_entry(self) << ",\n"
        end
      end
    end
    # enum definitions for the instruction set
    def write_inst_enum_entries(io="")
      ISET.each_with_index do |inst,num|
        name,cname = inst
        io << "#{cname} = 0x#{(num+inst_base).to_s(16)}, /* #{name} */\n"
      end
    end
    def bytecode_size
      maybe_generate
      @size
    end
    def write_bytecode_image(io="")
      maybe_generate
      @compiled_definitions.each do |cdef|
        next if cdef.definition.primitive?
        io << "/* #{cdef.definition.name} */ "
        io << cdef.code.map{|w|w.to_s(16).prepend("0x")}.join(", ")
        io << ",\n"
      end
    end
    # find a word in the compiled dictionary
    def get_word_address(wordname)
      d=@compiled_definitions.find{|cdef| cdef.definition.name == wordname } ||
        raise("word '#{wordname}' not found in compiled definitions")
      d.location
    end
    def int_bytes(val,width)
      [val].pack("I").unpack("C"*width)
    end
  end

  module ByteCode

    class Linux64 < ByteCodeImage
      def cell_width() 8 end
      def atom_size(elt)
        @sizes={
          MFPrim => 1,
          MFWord => 3,
          MFByteLit => 2,
          MFIntLit => 9 }
        s=@sizes[elt.class]
        raise "unknown element size: #{elt} of #{elt.class}" unless s
        s
      end
      def inst_base() 0x80 end
      # header includes lit instruction ( litc type count )
      def header_length() 3 end
    end

    class Cortex < ByteCodeImage
      def cell_width() 4 end
      def atom_size(elt)
        case elt
        when MFByteLit then 2
        when MFIntLit then 5
        when MFWord then
          if elt.definition.primitive?
            1
          else
            3
          end
        else
          raise "unknown element size: #{elt} of #{elt.class}" unless s
        end
      end
      def inst_base() 0xa0 end
      def header_length() 3 end
    end
  end
end