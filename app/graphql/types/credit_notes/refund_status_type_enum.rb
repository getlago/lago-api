# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Types
  module CreditNotes
    class RefundStatusTypeEnum < Types::BaseEnum
      graphql_name "CreditNoteRefundStatusEnum"

      CreditNote::REFUND_STATUS.each do |type|
        value type
      end
    end
  end
end
