require 'test/unit'
require 'mfactor/dot'
require 'tempfile'

class TestNode < Struct.new(:label, :children, :parents)
  def dot_label
    label
  end
  def dot_children
    children
  end
  def dot_parents
    parents
  end
end

class DotTest < Test::Unit::TestCase
  def test_simple_graph
    n1=TestNode.new("n1")
    n2=TestNode.new("n2")
    n3=TestNode.new("n3")
    n4=TestNode.new("n4")
    n1.children = [n1]
    n2.children = [n4]
    n4.parents = [n3]
    n3.parents = [n1]
    tf=Tempfile.open(["test","dot"]) do |f|
      n1.dot_code(f)
      f.close
      `dot -Tpng #{tf.path} -p /tmp/test_dot.png`
    end
  end
end
