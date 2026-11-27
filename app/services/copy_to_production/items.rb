# frozen_string_literal: true

module CopyToProduction
  module Items
    # Each item type of Copy to production, keyed by the GraphQL value.
    TYPES = {
      "billable_metric" => "CopyToProduction::Items::BillableMetricItem",
      "catalog_plan" => "CopyToProduction::Items::CatalogPlanItem",
      "coupon" => "CopyToProduction::Items::CouponItem",
      "feature" => "CopyToProduction::Items::FeatureItem",
      "plan_rate_card" => "CopyToProduction::Items::PlanRateCardItem",
      "pricing_unit" => "CopyToProduction::Items::PricingUnitItem",
      "product" => "CopyToProduction::Items::ProductItem",
      "product_category" => "CopyToProduction::Items::ProductCategoryItem",
      "rate_card" => "CopyToProduction::Items::RateCardItem",
      "tax" => "CopyToProduction::Items::TaxItem"
    }.freeze

    # Item types only copied along with an item that references them or that they belong to, never on their own.
    INTERNAL_TYPES = %w[pricing_unit rate_card tax].freeze

    def self.build(item_type, sandbox:, production:)
      TYPES.fetch(item_type.to_s).constantize.new(sandbox:, production:)
    end

    def self.copyable?(item_type)
      TYPES.key?(item_type.to_s) && INTERNAL_TYPES.exclude?(item_type.to_s)
    end
  end
end
