# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module OrderForms
    class StatusEnum < Types::BaseEnum
      graphql_name "OrderFormStatusEnum"

      OrderForm::STATUSES.each_key do |type|
        value type
      end
    end
  end
end
