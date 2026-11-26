# frozen_string_literal: true

module V2
  class ContractWalletSerializer < ModelSerializer
    include WalletAppliesTo

    timestamps :last_ongoing_balance_sync_at, :terminated_at, :created_at, :updated_at, :deleted_at

    expandable :taxes, serializer: ::V2::TaxSerializer
    expandable :metadata, serializer: ::V1::MetadataSerializer

    PRELOADS = [:contract, :customer, SELECTORS_PRELOAD].freeze

    def serialize
      {
        lago_id: model.id,
        lago_contract_id: model.contract_id,
        external_contract_id: model.contract.external_id,
        contract_code: model.contract.code,
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
        balance_cents: model.balance_cents,
        ongoing_balance_cents: model.ongoing_balance_cents
      }
    end

    private

    # The kept taxes, latest linked first.
    def taxes = model.taxes.merge(::CatalogWalletAppliedTax.order(::CursorPagination::DEFAULT_SORT))
  end
end
