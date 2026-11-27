# frozen_string_literal: true

module CopyToProduction
  module Items
    # Copied along with the rate cards it applies to. A copied tax applies to nothing else in production.
    class TaxItem < BaseItem
      ATTRIBUTES = %i[name code rate description].freeze

      def copy!(source, _resolved)
        Taxes::CreateService.call!(organization: production, params: source.slice(*ATTRIBUTES)).tax
      end

      # Taxes are not a resource of the activity log.
      def activity_type
        nil
      end
    end
  end
end
