require 'test/unit'
require 'mfactor/eval'
require 'tempfile'

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
  def test_enum_interface
    e1 = MFactor::Tokenizer.new(StringIO.new("3 items here")).each
    assert_equal "3", e1.next
    assert_equal "items", e1.next
    assert_equal "here", e1.next
  end
end

class EvalTest < Test::Unit::TestCase
  def setup
    @e = MFactor::Eval.new
  end
  def test_basic_eval
    @e.eval 1
    assert_equal [ 1 ],@e.pstack
    @e >> 2
    assert_equal [1,2], @e.pstack
  end
  def test_object_creation
    @e[MFactor::Vocabulary, :new]
    assert_instance_of MFactor::Vocabulary, @e.pstack[0]
    assert_equal  "__unnamed__", @e.pstack[0].name
  end
  def test_definition
    @e.define(:test_def,[1,2,:+])
    @e >> :test_def
    assert_equal [3], @e.pstack
  end
  def test_proc
    @e >> proc { push(:foo)}
    @e >> :call
    assert_equal [:foo],@e.pstack
  end
  def test_quotations
    @e >> [ 1, 2 ] >> :call
    assert_equal [1, 2], @e.pstack
    @e >> [ :+ ] >> :call
    assert_equal [3], @e.pstack
  end
  def test_token
    @e.open("that 123")
    @e[:token,:token]
    assert_equal ["that","123"],@e.pstack
    @e.clear
    tf=Tempfile.open('tokentest') do |f|
      f.puts "that","123"
      f.flush
      f.rewind
      @e.open f
      @e[:token,:token]
      assert_equal ["that","123"],@e.pstack
    end
  end
  def test_compose
    @e >> [ 1, 2 ] >> [ :+ ]
    @e >> :compose
    assert_instance_of Proc, @e.pstack[0]
    @e >> :call
    assert_equal [3], @e.pstack
  end
  def test_boot
    @e.boot
  end
end
