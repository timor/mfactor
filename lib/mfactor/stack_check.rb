require 'mfactor/image'
require 'parslet'

module MFactor

  def combine_effects(effect1, effect2)
    in1,out1 = effect1.dup
    in2,out2 = effect2.dup
    if in2.length > out1.length
      raise "not enough items on stack #{out1} for input effect #{in2}"
    else
      [in1,out1[0..-in2.length-1]+out2]
    end
  end

  def infer(body)
    e=nil
    body.each do |w|
      next_effect=
        case w
        when String then [[],[w]]
        when MFIntLit then [[],[w.value]]
        when MFWord then  w.definition.effect
        when Array then [[],[infer(w)]]
        end
      if e
        e=combine_effects(e,next_effect)
      else
        e=next_effect
      end
      pp e
    end
    e
  end


end
