# frozen_string_literal: true

module Invoices
  module ProviderTaxes
    class PullTaxesAndApplyJob < ApplicationJob
      queue_as 'integrations'

      def perform(invoice:)
        return unless invoice.customer.anrok_customer

        Invoices::ProviderTaxes::PullTaxesAndApplyService.call(invoice:)
      end
    end
  end
end
