# frozen_string_literal: true

module Wallets
  class RefreshCreditsService < BaseService
    def initialize(wallet:)
      @wallet = wallet
      super
    end

    def call
      customer.active_subscriptions.each do |subscription|
        usage_result = ::Invoices::CustomerUsageService.call(
          nil, # current_user
          customer_id: customer.external_id,
          subscription_id: subscription.external_id,
          organization_id: customer.organization_id,
        )
        usage_result.raise_if_error!

        prepaid_credit_result = Credits::AppliedPrepaidCreditService.call(invoice: usage_result.invoice, wallet:)
        prepaid_credit_result.raise_if_error!
      end

      result.wallet = wallet
      result
    end

    private

    attr_reader :wallet

    delegate :customer, to: :wallet
  end
end
