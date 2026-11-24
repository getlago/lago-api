# frozen_string_literal: true

module CopyToProduction
  module Items
    # Copied along with the rate cards priced in it.
    class PricingUnitItem < BaseItem
      def find_source(id)
        sandbox.pricing_units.find_by(id:)
      end

      def find_existing(source)
        production.pricing_units.find_by(code: source.code)
      end

      # As PricingUnits::CreateService, which needs a premium license.
      def refusal(_source)
        "feature_unavailable" unless License.premium?
      end

      def copy!(source, _resolved)
        PricingUnits::CreateService.call!(
          organization: production,
          **source.slice(:name, :code, :short_name, :description).symbolize_keys
        ).pricing_unit
      end

      def unique_indexes
        {"index_pricing_units_on_code_and_organization_id" => :code}
      end

      # Pricing units are not a resource of the activity log.
      def activity_type
        nil
      end
    end
  end
end
