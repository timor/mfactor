require 'test/unit'
require 'mfactor/dot'
require 'tempfile'
require 'fileutils'
include FileUtils

class TestNode < Struct.new(:label, :children, :parents, :siblings)
  include MFactor::DotNode
  def dot_label
    label
  end
  def child_nodes
    children||[]
  end
  def parent_nodes
    parents||[]
  end
  def sibling_nodes
    siblings||[]
  end
end
class TestPort<TestNode
  attr_accessor :record
  attr_accessor :position
  def dot_record
    [ @record, @position ]
  end
end

class DotTest < Test::Unit::TestCase
  def setup
    @n1=TestNode.new("n1")
    @n2=TestNode.new("n2")
    @n3=TestNode.new("n3")
    @n4=TestNode.new("n4")
    @n1.children = [@n2]
    @n2.children = [@n3]
    @n3.parents = [@n4]
    @n4.parents = [@n1]
  end
  def test_mixin
    nodes,transitions,node_names,records = @n1.collect
    assert_equal nodes,[@n1,@n2,@n4,@n3].to_set
  end
  def gen_dot_file(node,fname)
    tf=Tempfile.open(["test","dot"]) do |f|
      node.dot_code(f)
      f.close
      df="d:/temp/test_dot_#{fname}.dot"
      cp f.path, df
      `dot -Tpng #{df} -o d:/temp/test_dot_#{fname}.png`
    end
  end
  def _test_simple_graph
    gen_dot_file(@n1,"sgraph")
  end
  def _test_records
    i1=TestPort.new("i1")
    i2=TestPort.new("i2")
    nl=TestPort.new("opname")
    o1=TestPort.new("o1")
    o2=TestPort.new("o2")
    d=TestNode.new("d")
    o1.children=[d]
    o1.siblings=[i1,i2,nl,o2]
    [i1,i2,nl,o1,o2].each_with_index do |p,i|
      p.position=i
      p.record=:rec
    end
    gen_dot_file(o1,"rectest")
  end
end
