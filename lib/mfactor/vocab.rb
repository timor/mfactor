module MFactor

  # named container for definitions
  class Vocabulary
    attr_accessor :name
    attr_accessor :definitions
    attr_accessor :used_vocabs  # to store dependencies to other vocabs
    attr_accessor :definition_file # stores file where this vocab has been defined first
    def initialize(name="__unnamed__")
      @name=name
      @index={}
      @definitions=[]
      @used_vocabs = []
    end
    def see
      "IN: #{name}\n"+
        @definitions.map{|d| d.see}.join("\n")
    end
    def find(name)
      @index[name]
    end
    def add(definition)
      existing=@index[definition.name.to_s]
      if existing
        raise "#{definition.err_loc}: Error: trying to add duplicate word #{definition.name.to_s}" unless existing.deferred?
        raise "unable to remove old definition" unless @definitions.delete(existing)
      end
      @index[definition.name.to_s]=definition
      definition.vocabulary = self  # doubly link
      @definitions.push(definition)
    end
  end
end
