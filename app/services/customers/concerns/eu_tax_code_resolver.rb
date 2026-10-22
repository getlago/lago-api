# frozen_string_literal: true

module Customers
  module Concerns
    module EuTaxCodeResolver
      EU_TAX_CODE_PREFIX = "lago_eu"
      EU_TAX_EXEMPT_CODE = "lago_eu_tax_exempt"

      private

      # Custom taxes set on these customers take precedence over the EU exemption (e.g. a B2C VAT outside the EU).
      def non_eu_customer_without_tax_id?
        customer.billing_entity.eu_tax_management &&
          customer.tax_identification_number.blank? &&
          customer.country.present? &&
          !eu_countries_code.include?(customer.country.upcase)
      end

      def custom_tax_code?(code)
        !code.downcase.start_with?(EU_TAX_CODE_PREFIX)
      end

      def billing_country_code
        @billing_country_code ||= customer.billing_entity.country
      end

      def process_vies_tax(customer_vies)
        return "lago_eu_reverse_charge" unless billing_country_code.casecmp?(customer_vies[:country_code])

        standard_code = "lago_eu_#{billing_country_code.downcase}_standard"
        return standard_code if customer.zipcode.blank?
        return standard_code if applicable_tax_exceptions(country_code: customer_vies[:country_code]).blank?

        exception_code = applicable_tax_exceptions(country_code: customer_vies[:country_code]).first["name"].parameterize.underscore
        "lago_eu_#{customer_vies[:country_code].downcase}_exception_#{exception_code}"
      end

      def process_not_vies_tax
        return "lago_eu_#{billing_country_code.downcase}_standard" if customer.country.blank?
        return "lago_eu_#{customer.country.downcase}_standard" if eu_countries_code.include?(customer.country.upcase)

        "lago_eu_tax_exempt"
      end

      def eu_countries_code
        LagoEuVat::Rate.country_codes
      end

      def applicable_tax_exceptions(country_code:)
        @applicable_tax_exceptions ||= eu_country_exceptions(country_code:).select do |exception|
          customer.zipcode.match?(exception["postcode"])
        end
      end

      def eu_country_exceptions(country_code:)
        @eu_country_exceptions ||= LagoEuVat::Rate.country_rates(country_code:)[:exceptions]
      end

      def is_valid_vat_number?(vat_number)
        ::Valvat::Syntax.validate(vat_number)
      end
    end
  end
end
