require 'test/unit'
require 'mfactor/eval'

class TokenizerTest < Test::Unit::TestCase
  def string_tokens(s)
    MFactor::Tokenizer.new(StringIO.new(s)).to_a
  end
  def test_tokenize_steps
    t = MFactor::Tokenizer.new(StringIO.new("3 items here")).to_enum
    assert_equal "3", t.next
    assert_equal "items", t.next
    assert_equal "here", t.next
  end
  def test_tokenize_line
    tokens = string_tokens("this is a  line with 7 	elements.")
    assert_equal 7,tokens.length
    tokens = string_tokens("this is a  line with 7 	elements.")
    assert_equal 7,tokens.length
  end
  def test_tokenize_pos
    a = string_tokens("another test line\nanother  test 	line")
    assert_equal 6, a.length
    assert_equal [0,8,13,0,9,14], a.map{|t| t.column}
    assert_equal 1,a[0].line
    assert_equal 2,a[-1].line
  end
end

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
