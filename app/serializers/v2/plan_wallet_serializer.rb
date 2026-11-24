# frozen_string_literal: true

module V2
  class PlanWalletSerializer < ModelSerializer
    include WalletAppliesTo

    timestamps :created_at, :updated_at, :deleted_at

    expandable :taxes, serializer: ::V2::TaxSerializer
    expandable :metadata, serializer: ::V1::MetadataSerializer

    PRELOADS = [:catalog_plan, SELECTORS_PRELOAD].freeze

    def serialize
      {
        lago_id: model.id,
        plan_code: model.catalog_plan.code,
        code: model.code,
        name: model.name,
        invoice_display_name: model.invoice_display_name,
        currency: model.currency,
        tax_application: model.tax_application,
        priority: model.priority,
        applies_to:,
        top_up_min_amount_cents: model.top_up_min_amount_cents,
        top_up_max_amount_cents: model.top_up_max_amount_cents
      }
    end

    private

    # The kept taxes, latest linked first.
    def taxes = model.taxes.merge(::CatalogWalletAppliedTax.order(::CursorPagination::DEFAULT_SORT))
  end
end
