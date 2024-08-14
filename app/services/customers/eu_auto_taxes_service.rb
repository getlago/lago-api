# frozen_string_literal: true

require 'valvat'

module Customers
  class EuAutoTaxesService < BaseService
    def initialize(customer:)
      @customer = customer
      @organization_country_code = customer.organization.country

      super
    end

    def call
      customer_vies = vies_check

      return process_vies_tax(customer_vies) if customer_vies.present?

      process_not_vies_tax
    end

    private

    attr_reader :customer, :organization_country_code

    def vies_check
      vies_check = Valvat.new(customer.tax_identification_number).exists?(detail: true)
      after_commit { SendWebhookJob.perform_later('customer.vies_check', customer, vies_check:) }

      vies_check
    end

    def process_vies_tax(customer_vies)
      return 'lago_eu_reverse_charge' unless organization_country_code.casecmp?(customer_vies[:country_code])

      standard_code = "lago_eu_#{organization_country_code.downcase}_standard"
      return standard_code if customer.zipcode.blank?
      return standard_code if applicable_tax_exceptions(country_code: customer_vies[:country_code]).blank?

      exception_code = applicable_tax_exceptions(country_code: customer_vies[:country_code]).first['name'].parameterize.underscore
      "lago_eu_#{customer_vies[:country_code].downcase}_exception_#{exception_code}"
    end

    def process_not_vies_tax
      return "lago_eu_#{organization_country_code.downcase}_standard" if customer.country.blank?
      return "lago_eu_#{customer.country.downcase}_standard" if eu_countries_code.include?(customer.country.upcase)

      'lago_eu_tax_exempt'
    end

    def eu_countries_code
      LagoEuVat::Rate.new.countries_code
    end

    def applicable_tax_exceptions(country_code:)
      @applicable_tax_exceptions ||= eu_country_exceptions(country_code:).select do |exception|
        customer.zipcode.match?(exception['postcode'])
      end
    end

    def eu_country_exceptions(country_code:)
      @eu_country_exceptions ||= LagoEuVat::Rate.new.country_rates(country_code:)[:exceptions]
    end
  end
end
