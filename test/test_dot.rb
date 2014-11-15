require 'test/unit'
require 'mfactor/graph'
require 'mfactor/stack'
require 'tempfile'
require 'fileutils'
require 'tmpdir'
include FileUtils

class TestNode < Struct.new(:label,:shape)
  include MFactor::GraphNode
  def dot_label
    label
  end
  def dot_node_shape
    if shape
      shape
    else
      "circle"
    end
  end
end
class TestPort < Struct.new(:label, :record, :position)
  include MFactor::GraphNode
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
  include MFactor::GraphNode
end

class DotTest < Test::Unit::TestCase
  def setup
    @g=MFactor::CDFG.new
  end
  def setup_d_graph
    @n1=TestNode.new("n1")
    @n2=TestNode.new("n2")
    @n3=TestNode.new("n3")
    @n4=TestNode.new("n4")
    @g.add_control_edge @n1, @n2
    @g.add_control_edge @n2, @n3
    @g.add_control_edge @n4, @n3
    @g.add_control_edge @n1, @n4
  end
  def test_dot_available
    assert_nothing_raised do
      puts "if this test failed, graphviz is not installed"
      sh "dot -h"
    end
  end
  def test_creation
    n1=TestNode.new("asd")
    assert_block do
      n1.is_a? MFactor::GraphNode
    end
    assert_respond_to n1, :record
    assert_respond_to n1, :is_record?
    n2=TestRecordNode.new
    assert_block do
      n2.is_a? MFactor::GraphNode
    end
    assert_block do
      n2.is_a? MFactor::DotRecord
    end
    g1=MFactor::CDFG.new
    assert_respond_to g1, :dot
    assert_respond_to g1, :add_control_edge
    assert_respond_to g1, :add_data_edge
    assert_respond_to g1, :add_node
  end
  def gen_dot_file(graph,fname)
    tf=Tempfile.open(["test","dot"]) do |f|
      graph.dot(f)
      f.close
      df="#{Dir.tmpdir}/test_dot_#{fname}.dot"
      cp f.path, df
      `dot -Tpng #{df} -o #{Dir.tmpdir}/test_dot_#{fname}.png`
    end
  end
  def test_simple_graph
    setup_d_graph
    gen_dot_file(@g,"sgraph")
  end
  def test_records
    c1=TestNode.new("c1")
    i1=TestPort.new("i1")
    i2=TestPort.new("i2")
    nl=TestPort.new("opname")
    o1=TestPort.new("o1")
    o2=TestPort.new("o2")
    d=TestNode.new("d")
    rec = TestRecordNode.new
    @g.add_data_edge o1, d
    [i1,i2,nl,o2].each do |n|
      @g.add_node n
    end
    [i1,i2,nl,o1,o2].each do |n|
      rec.add_port n
    end
    @g.add_control_edge c1,rec
    gen_dot_file(@g,"rectest")
  end
  def test_node_shape
    ni=TestIfNode.new("c==1")
    @g.add_control_edge ni,TestNode.new("c1")
    @g.add_control_edge ni, TestNode.new("c2")
    gen_dot_file(@g,"shapetest")
  end
  def test_record_only
    setup_d_graph
    r=TestRecordNode.new
    [@n1,@n2,@n3,@n4].each do |n|
      r.add_port n
    end
    assert_equal TestRecordNode, r.class
    @g.add_node r
    gen_dot_file(@g,"reconly")
  end
  def test_stack_record
    i1=MFactor::MFInput.new("i1",:t)
    i2=MFactor::MFInput.new("i2",:t)
    s=MFactor::MFStack.new([i1,i2])
    @g.add_node s
    gen_dot_file(@g,"istack_by_rec")
  end
end
