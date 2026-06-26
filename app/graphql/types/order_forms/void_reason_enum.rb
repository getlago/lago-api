# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module OrderForms
    class VoidReasonEnum < Types::BaseEnum
      graphql_name "OrderFormVoidReasonEnum"

      OrderForm::VOID_REASONS.each_key do |type|
        value type
      end
    end
  end
end
