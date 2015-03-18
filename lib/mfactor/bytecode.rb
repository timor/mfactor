# the code that actually emits something from a already parsed mfactor file set
# performs dictionary validation among other stuff


require 'mfactor/image'

module MFactor

  # holds specialized compiled information
  class MFCompiledDefinition < Struct.new(:definition,:location,:code,:flags)
    def write_dict_entry(bytecode,io="")
      loc = definition.primitive? ? "0x#{(location << (8*(bytecode.cell_width-1))).to_s(16)}" : "&image+#{location.to_s}"
      io <<
        "{ .address = (inst *)#{loc}, .flags = #{flags}, .name = #{definition.name.to_s.inspect}, .name_length=#{definition.name.to_s.length}}"
    end
  end


  # expect to be created with already loaded MFactor instance
  class ByteCodeImage < Image
    HEADER_TYPES={ data: 0, quotation: 1, base_ref: 2, long_ref: 3, boxed: 4 }
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
      @dict_positions={}    # store dictionary addresses
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
      # image=[] # TBR?
      @memloc=0
      def_list=@dictionary.values.map{|v| v.definitions}.flatten.reject{|d| d.primitive?}
      def_list.each do |d|
        code=[]
        cdef=MFCompiledDefinition.new
        cdef.location=@memloc
        cdef.definition=d
        cdef.flags=(cdef.definition.definer == "SYNTAX:" ? 1 : 0)
        @compiled_definitions << cdef # adding here already although body may be empty
        # determine code size beforehand to get offset for data segment of definition
        defsize=d.code.body.map{|w| element_size(w)}.reduce(:+) +1 # final qend
        @data=[]
        @data_counter=@memloc+defsize # initialize data segment counter
        puts "compiling definition for #{d.name}" if Rake.verbose == true
        d.code.body.each do |word|
          word_bytecode(word,code)
        end
        code << prim(:qend)
        puts "#{d.name} is at #{@memloc}" if Rake.verbose == true
        @memloc += (defsize + @data.length)
        cdef.code=code+@data
      end
      @size=@memloc
      puts "total bytecode size: #{@memloc}" if Rake.verbose
      puts "memory map:" if Rake.verbose
      @compiled_definitions.each do |d|
        puts "@#{d.location}: #{d.definition.name} #{d.definition.primitive? ? 'prim' : '' }"
        print d.code
        puts ";" if d.code
      end if Rake.verbose == true
      print ISET.keys.map{ |name| [name,prim(name)] },"\n" if Rake.verbose == true
      # need to actually generate the dictionary here, and do a second pass substituting all wrapped words
      calculate_dict_entries
      # replace all placeholders with dictionary offsets
      @compiled_definitions.each do |cdef|
        cdef.code.each_with_index do |w,i|
          if w.is_a? Array and w[0] == :dict_address
            addr = @dict_positions[w[1]]
            cdef.code[i,cell_width]=int_bytes(addr,cell_width)
          end
        end
      end
      check_locations
      @generated = true
      # @compiled_definitions.map{|d| d.code}.flatten
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
    # element size in quotation context
    def element_size(elt)
      case elt
      when MFStringLit then header_length + elt.value.chars.to_a.length
      when Quotation then 3 + elt.body.map{|e| element_size(e)}.reduce(:+)
      when MFLitSequence then header_length + elt.element_size * elt.content.length
      when MFComplexSequence then 3
      when WrappedWord then
        # replaced by [ dictstart liti offset[0,3] + ]
        1 + 1 + cell_width + 1
      else atom_size(elt)
      end
    end
    def inline_seq_header(elt_type, elt_size, count, image)
      raise "inline sequences longer than 255 elements not supported!" if count > 255
      # size_indicator=Rational(Math::log2(elt_size))
      size_indicator = elt_size - 1
      raise "element size too big: #{elt_size}" if size_indicator > 7
      image << prim(:litc) << (0 | (elt_type << 3) | size_indicator) << count
    end
    # escape c chars
    def escape_c_char c
      n = c.ord
      if (n < 33) or (n == 39) or (n == 92)
        "\\x#{c.ord.to_s(16)}"
      else
        c
      end
    end
    # generate bytecode in data segment, return address
    def generate_data(item)
      acc = []
      case item
      when MFComplexSequence
        inline_seq_header(HEADER_TYPES[:boxed], cell_width + 1, item.content.length, acc)
        item.content.each do |elt|
          if elt.is_a? MFIntLit
            type = HEADER_TYPES[:data]
            content = int_bytes(elt.value,cell_width)
          else
            type = HEADER_TYPES[:base_ref]
            content = int_bytes(generate_data(elt),2)+[0,0]
          end
          acc << type
          acc.concat content
        end
      when Quotation
        puts "generating non-inline quotation: #{item} " if Rake.verbose == true
        inline_seq_header(HEADER_TYPES[:quotation], 1, quotation_length(item.body), acc)
        item.body.each {|w| word_bytecode(w,acc)}
        acc << prim(:qend)
      when MFStringLit then word_bytecode(item,acc)
      when MFLitSequence then word_bytecode(item,acc)
      else
        raise "cannot generate data segment for #{item.class}"
      end
      loc = @data_counter
      puts "constant data at #{loc} " if Rake.verbose == true
      @data.concat acc
      @data_counter += acc.length
      return loc + 2            # referenced address should point to count byte
    end
    def quotation_length(arr)
      l=arr.map{|e| element_size(e)}.reduce(:+)
      raise "quotations with more than 255 elements unsupported" if l > 255
      l
    end
    # generate byte code for one word, append to image
    def word_bytecode(word,image)
      case word
      when MFStringLit then
        inline_seq_header(HEADER_TYPES[:data],1,word.value.chars.to_a.length,image)
        image.concat word.value.chars.map{|c| "'#{escape_c_char(c)}'"}
      when Quotation then
        image << prim(:qstart)
        image << quotation_length(word.body)
        word.body.map{|w| word_bytecode(w,image)}
        image << prim(:qend)      # maybe omit, check space savings
      when MFComplexSequence then
        image << prim(:bref)
        image.concat int_bytes(generate_data(word),2)
      when MFLitSequence then
        inline_seq_header(HEADER_TYPES[:data],word.element_size,word.content.length,image)
        word.content.map{|w| image.concat int_bytes(w.value,word.element_size)}
      when MFByteLit then image << prim(:litb) << word.value
      when MFIntLit then (image << prim(:liti)).concat int_bytes(word.value,cell_width)
      when MFWord then
        if word.definition.primitive?
          if word.is_tail && word.name == "call"
            image << prim(:stcall)
          else
            image << prim(word.name)
          end
        else
          # puts "referring to #{word.name}"
          image << ( word.is_tail ? prim(:btcall) : prim(:bcall) )
          image.concat bcall_bytes(@compiled_definitions.find{|cdef| cdef.definition==word.definition}.location)
        end
      when WrappedWord
        # replaced by [ dictstart liti offset[0,3] + ]
        image << prim(:dictstart) << prim(:liti) << [:dict_address, word.name]
        image.concat Array.new(cell_width()-1,0)
        image << prim(:+)
      else raise "don't know how to compile #{word}"
      end
    end
    def prim?(name)
      @prims[name.to_s]
    end
    def prim(name)
      ISET[name.to_s] || raise( "unknown primitive: #{name}")
    end
    def calculate_dict_entries
      i = 0
      @compiled_definitions.each do |cdef|
        next if cdef.definition.name.to_s[0] == "_"
        puts "dictionary entry for #{cdef.definition.name} is at offset #{i}" if Rake.verbose == true
        @dict_positions[cdef.definition.name.to_s] = i
        l = cell_width+3+cdef.definition.name.to_s.length + 1
        puts "length: #{l}" if Rake.verbose == true
        i += l
      end
    end
    # c code generation:
    # c99 initializers for the dictionary
    def write_dictionary_entries(io="")
      maybe_generate
      @compiled_definitions.each do |cdef|
        if cdef.definition.name.to_s[0] == "_"
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
    # output select locations directly as defines
    def write_word_positions(wordhash,io="")
      wordhash.each do |factorname, cname|
        io << "#define " << cname << " (&(image[" << get_word_address(factorname) << "]))\n"
#        io << "#define " << cname << " " << get_word_address(factorname) << "\n"
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
        io << "/* #{cdef.location}: #{cdef.definition.name} */ "
        io << cdef.code.map{|w| w.is_a?(Integer) ?  w.to_s(16).prepend("0x") : w}.join(", ")
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
          raise "unknown element size: #{elt} of #{elt.class}"
        end
      end
      def inst_base() 0xa0 end
      def header_length() 3 end
    end
  end
end
