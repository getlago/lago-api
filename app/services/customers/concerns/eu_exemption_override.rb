# frozen_string_literal: true

module Customers
  module Concerns
    # Custom taxes set on a customer outside the EU without tax ID (e.g. a B2C VAT) replace the EU exemption.
    module EuExemptionOverride
      EU_TAX_CODE_PREFIX = "lago_eu"
      EU_TAX_EXEMPT_CODE = "lago_eu_tax_exempt"

      private

      def eu_exemption_overridable?
        customer.billing_entity.eu_tax_management &&
          customer.tax_identification_number.blank? &&
          customer.country.present? &&
          LagoEuVat::Rate.country_codes.exclude?(customer.country.upcase)
      end

      def custom_tax_code?(code)
        !code.downcase.start_with?(EU_TAX_CODE_PREFIX)
      end
    end
  end
end
