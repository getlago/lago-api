# frozen_string_literal: true

module LagoFormula
  class BinaryOperation < Treetop::Runtime::SyntaxNode
    def evaluate(context = {})
      tail.elements.inject(head.evaluate(context)) do |value, element|
        element.operator.apply(value, element.operand.evaluate(context))
      end
    end
  end
end
