require 'mfactor/datatypes'

module MFactor
  # reopen
  class FriedQuotation
    def expand
      data_items=[]
      body.each do |elt|
        if elt.is_a? MFWord and elt.name.to_s == "_"
    end
  end
end
