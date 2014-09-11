module MFactor

  # named container for definitions
  class MFVocabulary
    attr_accessor :name
    attr_accessor :definitions
    def initialize(name)
      @name=name
      @index={}
      @definitions=[]
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
      raise "#{definition.err_loc}: Error: trying to add duplicate word #{definition.name.to_s}" if existing
      @index[definition.name.to_s]=definition
      definition.vocabulary = self  # doubly link
      @definitions.push(definition)
    end
  end
end
