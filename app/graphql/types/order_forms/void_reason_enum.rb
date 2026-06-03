# frozen_string_literal: true

module Types
  module OrderForms
    class VoidReasonEnum < Types::BaseEnum
      graphql_name "OrderFormVoidReasonEnum"

      OrderForm::VOID_REASONS.keys.each do |type|
        value type
      end
    end
  end
end
