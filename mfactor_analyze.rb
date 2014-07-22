require_relative 'mfactor'

class MFStaticCompile
  attr_acccessor :mf
  def initialize(mf)
    @mf=mf
  end
  def compile_word(name)
    defi=@mf.find_name name
    raise "definition of #{name} not found" unless defi
    
