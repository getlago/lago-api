# frozen_string_literal: true

module CopyToProduction
  module Items
    # Copied along with the rate cards priced in it.
    class PricingUnitItem < BaseItem
      ATTRIBUTES = %i[name code short_name description].freeze

      def copy!(source, _resolved)
        PricingUnits::CreateService.call!(organization: production, **source.slice(*ATTRIBUTES).symbolize_keys).pricing_unit
      end

      # Pricing units are not a resource of the activity log.
      def activity_type
        nil
      end
    end
  end
end
