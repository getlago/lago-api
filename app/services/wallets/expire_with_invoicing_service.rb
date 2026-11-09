# frozen_string_literal: true

module Wallets
  class ExpireWithInvoicingService < BaseService
    Result = BaseResult[:wallet]

    def initialize(wallet:)
      @wallet = wallet

      super
    end

    def call
      if wallet.active? && wallet.expiration_invoicing_enabled? && wallet.balance_cents.positive?
        subscriptions.find_each { |subscription| invoice_usage(subscription) }
      end

      # A failed expiration invoice spends the wallet when it is retried, so the wallet stays active until then.
      unless expiration_invoice_failed?
        # Applying the wallet credits updates its row, which bumps lock_version.
        Wallets::TerminateService.call!(wallet: wallet.reload)
      end

      result.wallet = wallet
      result
    end

    private

    attr_reader :wallet

    def expiration_invoice_failed?
      wallet.organization.invoices.failed
        .joins(:applied_wallet_expiration)
        .where(applied_wallet_expirations: {wallet_id: wallet.id})
        .exists?
    end

    def subscriptions
      wallet.customer.subscriptions.active.joins(:plan).where(plans: {amount_currency: wallet.currency})
    end

    def invoice_usage(subscription)
      invoice_result = Invoices::ProgressiveBilling::WalletExpirationService.call(wallet:, subscription:)

      # An idempotency error means a previous run already invoiced this subscription for this wallet.
      if invoice_result.failure? && !invoice_result.error.is_a?(Idempotency::IdempotencyError)
        invoice_result.raise_if_error!
      end
    end
  end
end
