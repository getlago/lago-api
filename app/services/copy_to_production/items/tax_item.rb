# frozen_string_literal: true

module CopyToProduction
  module Items
    # Copied along with the rate cards it applies to. A copied tax applies to nothing else in production.
    class TaxItem < BaseItem
      def find_source(id)
        sandbox.taxes.find_by(id:)
      end

      def find_existing(source)
        production.taxes.find_by(code: source.code)
      end

      def copy!(source, _resolved)
        Taxes::CreateService.call!(organization: production, params: source.slice(:name, :code, :rate, :description)).tax
      end

      def unique_indexes
        {"idx_unique_tax_code_per_organization" => :code}
      end

      # Taxes are not a resource of the activity log.
      def activity_type
        nil
      end
    end
  end
end
