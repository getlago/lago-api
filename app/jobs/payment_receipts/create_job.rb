# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module PaymentReceipts
  class CreateJob < ApplicationJob
    queue_as :low_priority

    def perform(payment)
      PaymentReceipts::CreateService.call!(payment:)
    end
  end
end
