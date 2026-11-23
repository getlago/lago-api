# frozen_string_literal: true

module CopyToProduction
  module Items
    # Each item type a user can copy from a sandbox to its production, keyed by the GraphQL value.
    TYPES = {
      "billable_metric" => "CopyToProduction::Items::BillableMetricItem",
      "feature" => "CopyToProduction::Items::FeatureItem",
      "coupon" => "CopyToProduction::Items::CouponItem"
    }.freeze

    def self.build(item_type, sandbox:, production:)
      TYPES.fetch(item_type.to_s).constantize.new(sandbox:, production:)
    end
  end
end
