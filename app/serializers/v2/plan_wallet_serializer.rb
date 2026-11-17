# frozen_string_literal: true

module V2
  class PlanWalletSerializer < ModelSerializer
    timestamps :created_at, :updated_at, :deleted_at

    expandable :taxes, serializer: ::V2::TaxSerializer
    expandable :metadata, serializer: ::V1::MetadataSerializer

    SELECTOR_TARGETS = [:product_category, :product, {product_filter: :product}].freeze

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
        applies_to: {include: selectors},
        top_up_min_amount_cents: model.top_up_min_amount_cents,
        top_up_max_amount_cents: model.top_up_max_amount_cents
      }
    end

    private

    # In the order they were added, sorted in memory so that a list reads its preloaded selectors.
    # Their targets load in one query per kind, also for a wallet that no request preloaded.
    def selectors
      selectors = model.selectors.sort_by { [it.created_at, it.id] }
      ActiveRecord::Associations::Preloader.new(records: selectors, associations: SELECTOR_TARGETS).call
      selectors.map { selector(it) }
    end

    # Each selector as a request names it.
    def selector(selector)
      case selector.selector_type
      when "fee_type"
        {type: "fee_type", code: selector.fee_type}
      when "product_category"
        {type: "product_category", code: selector.product_category.code}
      when "product"
        {type: "product", code: selector.product.code, with_product_filters: selector.with_product_filters}
      when "product_filters"
        {type: "product_filters", product_code: selector.product_filter.product.code, code: selector.product_filter.code}
      end
    end

    # The kept taxes, latest linked first.
    def taxes = model.taxes.merge(::CatalogWalletAppliedTax.order(::CursorPagination::DEFAULT_SORT))
  end
end
