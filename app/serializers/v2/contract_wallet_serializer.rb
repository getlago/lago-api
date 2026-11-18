# frozen_string_literal: true

module V2
  class ContractWalletSerializer < ModelSerializer
    include WalletAppliesTo

    timestamps :terminated_at, :created_at, :updated_at, :deleted_at

    expandable :taxes, serializer: ::V2::TaxSerializer
    expandable :metadata, serializer: ::V1::MetadataSerializer

    PRELOADS = [:contract, :customer, SELECTORS_PRELOAD].freeze

    def serialize
      {
        lago_id: model.id,
        external_contract_id: model.contract.external_id,
        external_customer_id: model.customer.external_id,
        code: model.code,
        name: model.name,
        invoice_display_name: model.invoice_display_name,
        currency: model.currency,
        tax_application: model.tax_application,
        priority: model.priority,
        applies_to:,
        top_up_min_amount_cents: model.top_up_min_amount_cents,
        top_up_max_amount_cents: model.top_up_max_amount_cents,
        balance:,
        # Usage not invoiced yet is not deducted so far, so the ongoing balance reads as the balance.
        ongoing_balance: balance
      }
    end

    private

    # A decimal string in the wallet currency, at its minor-unit precision.
    def balance = Money.new(model.balance_cents, model.currency).to_s

    # The kept taxes, latest linked first.
    def taxes = model.taxes.merge(::CatalogWalletAppliedTax.order(::CursorPagination::DEFAULT_SORT))
  end
end
