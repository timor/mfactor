require_relative 'mfactor'

class MFStack < Array
  def swap
    tmp = self[-1]
    self[-1]=self[-2]
    self[-2]=tmp
  end
  def drop() pop end
  def dup() push self[-1] end
end

class MFStaticCompile
  attr_acccessor :mf
  def initialize(mf)
    @mf=mf
  end
end
