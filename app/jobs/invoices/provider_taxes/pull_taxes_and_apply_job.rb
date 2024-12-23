# frozen_string_literal: true

module Invoices
  module ProviderTaxes
    class PullTaxesAndApplyJob < ApplicationJob
      include ConcurrencyThrottlable

      queue_as 'integrations'

      retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25

      def perform(invoice:)
        Invoices::ProviderTaxes::PullTaxesAndApplyService.call(invoice:)
      end
    end
  end
end
