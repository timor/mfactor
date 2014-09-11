require 'test/unit'
require 'mfactor/eval'

class EvalTest < Test::Unit::TestCase
  def test_basic_eval
    e = MFactor::Eval.new
    e.eval 1
    assert_equal e.pstack, [ 1 ]
    e >> 2
    assert_equal e.pstack, [1,2]
  end
  def test_object_creation
    e = MFactor::Eval.new
    e[MFactor::Vocabulary, :new]
    assert_instance_of MFactor::Vocabulary, e.pstack[0]
    assert_equal e.pstack[0].name, "__unnamed__"
  end
  def test_defnition
    e = MFactor::Eval.new
    e.define(:test_def,[1,2,:+])
    e >> :test_def
    assert_equal e.pstack,[3]
  end
  def test_proc
    e = MFactor::Eval.new
    e >> proc { push(:foo)}
    assert_equal e.pstack,[:foo]
  end
  def test_boot
    e = MFactor::Eval.new
    e.define(:token,[])
  end
end
