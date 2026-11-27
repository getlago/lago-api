# frozen_string_literal: true

module V2
  class ContractWalletTransactionSerializer < ModelSerializer
    timestamps :settled_at, :failed_at, :created_at, :updated_at

    PRELOADS = %i[catalog_wallet credit_allocation].freeze

    def serialize
      {
        lago_id: model.id,
        lago_wallet_id: model.catalog_wallet_id,
        wallet_code: model.catalog_wallet.code,
        lago_invoice_id: model.invoice_id,
        lago_credit_allocation_id: model.credit_allocation_id,
        credit_allocation_code: model.credit_allocation&.code,
        direction: model.direction,
        status: model.status,
        reason: model.reason,
        allocation_type: model.allocation_type,
        currency: model.catalog_wallet.currency,
        purchase_amount_cents: model.purchase_amount_cents,
        credit_amount_cents: model.credit_amount_cents,
        remaining_credit_amount_cents: model.remaining_credit_amount_cents,
        priority: model.inbound? ? model.priority : nil
      }
    end
  end
end
