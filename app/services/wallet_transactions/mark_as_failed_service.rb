# frozen_string_literal: true

module WalletTransactions
  class MarkAsFailedService < BaseService
    Result = BaseResult[:wallet_transaction]

    SETTLED_FAILURE_WEBHOOK = "wallet_transaction.payment_failure_after_settlement"

    def initialize(wallet_transaction:, notify_settled_failure: false)
      @wallet_transaction = wallet_transaction
      @notify_settled_failure = notify_settled_failure
      super
    end

    activity_loggable(
      action: "wallet_transaction.updated",
      record: -> { wallet_transaction }
    )

    def call
      return result unless wallet_transaction
      return result if wallet_transaction.failed?

      if wallet_transaction.settled?
        # note: credits were already granted, they can only be voided manually
        notify_settled_failure! if notify_settled_failure
        return result
      end

      wallet_transaction.mark_as_failed!
      after_commit { SendWebhookJob.perform_later("wallet_transaction.updated", wallet_transaction) }

      result.wallet_transaction = wallet_transaction
      result
    end

    private

    attr_reader :wallet_transaction, :notify_settled_failure

    def notify_settled_failure!
      return if Webhook.exists?(object: wallet_transaction, webhook_type: SETTLED_FAILURE_WEBHOOK)

      after_commit { SendWebhookJob.perform_later(SETTLED_FAILURE_WEBHOOK, wallet_transaction) }
    end
  end
end
