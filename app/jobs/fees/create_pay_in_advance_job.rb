# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceJob < ApplicationJob
    queue_as :default

    unique :until_executed, on_conflict: :log

    def perform(charge:, event:, billing_at: nil)
      result = Fees::CreatePayInAdvanceService.call(charge:, event:, billing_at:)

      return if !result.success? && tax_error?(result)

      result.raise_if_error!
    end

    private

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error&.messages&.dig(:tax_error)
    end
  end
end
