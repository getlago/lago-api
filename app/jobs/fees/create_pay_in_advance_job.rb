# frozen_string_literal: true

module Fees
  class CreatePayInAdvanceJob < ApplicationJob
    queue_as :default

    retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25

    unique :until_executed, on_conflict: :log

    def perform(charge:, event:, billing_at: nil)
      result = Fees::CreatePayInAdvanceService.call(charge:, event:, billing_at:)

      return if !result.success? && tax_error?(result)

      result.raise_if_error!
    end

    def lock_key_arguments
      args = arguments.first
      event = Events::CommonFactory.new_instance(source: args[:event])
      [args[:charge], event.organization_id, event.external_subscription_id, event.transaction_id]
    end

    private

    def tax_error?(result)
      return false unless result.error.is_a?(BaseService::ValidationFailure)

      result.error&.messages&.dig(:tax_error).present?
    end
  end
end
