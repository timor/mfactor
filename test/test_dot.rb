require 'test/unit'
require 'mfactor/dot'
require 'tempfile'
require 'fileutils'
include FileUtils

class TestNode < Struct.new(:label)
  include MFactor::DotNode
  def dot_label
    label
  end
end
class TestPort < Struct.new(:label, :record, :position)
  include MFactor::DotNode
  def dot_record
    [ record, position ]
  end
  def dot_label
    label
  end
end
class TestIfNode<TestNode
  def dot_node_shape
    return "diamond"
  end
end
class TestRecordNode
  include MFactor::DotRecord
end

class DotTest < Test::Unit::TestCase
  def setup_d_graph
    @n1=TestNode.new("n1")
    @n2=TestNode.new("n2")
    @n3=TestNode.new("n3")
    @n4=TestNode.new("n4")
    @n1.add_child @n2
    @n2.add_child @n3
    @n3.add_parent @n4
    @n4.add_parent @n1
  end
  def test_creation
    n1=TestNode.new("asd")
    assert_block do
      n1.is_a? MFactor::DotNode
    end
    assert_respond_to n1, :add_parent
    assert_respond_to n1, :add_child
    assert_respond_to n1, :add_sibling
  end
  def test_mixin
    setup_d_graph
    nodes,transitions,node_names,records = @n1.collect
    assert_equal [@n1,@n2,@n4,@n3].to_set, nodes
  end
  def gen_dot_file(node,fname)
    tf=Tempfile.open(["test","dot"]) do |f|
      node.dot_graph(f)
      f.close
      df="d:/temp/test_dot_#{fname}.dot"
      cp f.path, df
      `dot -Tpng #{df} -o d:/temp/test_dot_#{fname}.png`
    end
  end
  def test_simple_graph
    setup_d_graph
    gen_dot_file(@n1,"sgraph")
  end
  def test_records
    i1=TestPort.new("i1")
    i2=TestPort.new("i2")
    nl=TestPort.new("opname")
    o1=TestPort.new("o1")
    o2=TestPort.new("o2")
    d=TestNode.new("d")
    rec = TestRecordNode.new
    o1.add_child d
    o1.add_sibling i1,i2,nl,o2
    rec.add_port i1,i2,nl,o1,o2
    gen_dot_file(o1,"rectest")
  end
  def test_node_shape
    ni=TestIfNode.new("c==1")
    ni.add_child TestNode.new("c1"), TestNode.new("c2")
    gen_dot_file(ni,"shapetest")
  end
end
