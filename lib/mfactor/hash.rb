# take a list of compiled definitions, return an ordering for the dictionary along with a
# hashtable for indexing

module MFactor
  # compute the hash for all entries, bin, return bins
  def hash_string(s,modulus)
    hash = 5381
    s.chars.each do |c|
      hash = (hash*33) + c.ord
    end
    hash % modulus
  end
  module_function :hash_string
  def dictionary_hash_table cdefs
    result = {}
    modulus = [256,cdefs.length/2].min
    cdefs.each do |cdef|
      name = cdef.definition.name.to_s
      hash = hash_string(name, modulus)
      if result[hash]
        result[hash].push cdef
      else
        result[hash] = [cdef]
      end
    end
    result
  end
  module_function :dictionary_hash_table
end
