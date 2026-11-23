# frozen_string_literal: true

module Wallets
  class ExpireWithInvoicingService < BaseService
    Result = BaseResult[:wallet]

    def initialize(wallet:, retrying: false)
      @wallet = wallet
      @retrying = retrying

      super
    end

    # The expiration can be pushed back after the clock enqueued the job.
    def call
      if wallet.expired?
        invoice_usage if invoice_usage?

        # Applying the wallet credits updates its row, which bumps lock_version.
        Wallets::TerminateService.call!(wallet: wallet.reload) unless expiration_invoice_unsettled?
      end

      result.wallet = wallet
      result
    end

    private

    attr_reader :wallet, :retrying

    # An unsettled expiration invoice still spends the wallet when its taxes are applied or when it is retried.
    def expiration_invoice_unsettled?
      AppliedWalletExpiration.where(wallet_id: wallet.id).with_unsettled_invoice.exists?
    end

    # The usage is invoiced once: a retry of the job finishes the subscriptions its failed attempt did not invoice,
    # later runs only wait for the expiration invoices to settle.
    def invoice_usage?
      return false unless wallet.active? && wallet.expiration_invoicing_enabled?

      retrying || !wallet.reserved_for_expiration_invoice?
    end

    def invoice_usage
      subscriptions.where.not(id: invoiced_subscription_ids).find_each do |subscription|
        invoice_subscription_usage(subscription)
      end
    end

    def subscriptions
      wallet.customer.subscriptions.active.joins(:plan).where(plans: {amount_currency: wallet.currency})
    end

    def invoiced_subscription_ids
      InvoiceSubscription
        .joins(invoice: :applied_wallet_expiration)
        .where(applied_wallet_expirations: {wallet_id: wallet.id})
        .select(:subscription_id)
    end

    def invoice_subscription_usage(subscription)
      invoice_result = Invoices::ProgressiveBilling::WalletExpirationService.call(wallet:, subscription:)

      # An idempotency error means a previous run already invoiced this subscription for this wallet.
      if invoice_result.failure? && !invoice_result.error.is_a?(Idempotency::IdempotencyError)
        invoice_result.raise_if_error!
      end
    end
  end
end
