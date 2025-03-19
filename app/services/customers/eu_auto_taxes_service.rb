# frozen_string_literal: true

require "valvat"

module Customers
  class EuAutoTaxesService < BaseService
    Result = BaseResult[:tax_code]

    def initialize(customer:, new_record:, tax_attributes_changed:)
      @customer = customer
      @organization_country_code = customer.organization.country
      @new_record = new_record
      @tax_attributes_changed = tax_attributes_changed

      super
    end

    def call
      return result.not_allowed_failure!(code: "eu_tax_not_applicable") unless should_apply_eu_taxes?

      customer_vies = vies_check

      result.tax_code = if customer_vies.present?
        process_vies_tax(customer_vies)
      else
        process_not_vies_tax
      end

      result
    end

    private

    attr_reader :customer, :organization_country_code, :tax_attributes_changed, :new_record

    def vies_check
      return nil if customer.tax_identification_number.blank?

      vies_check = Valvat.new(customer.tax_identification_number).exists?(detail: true)
      after_commit { SendWebhookJob.perform_later("customer.vies_check", customer, vies_check:) }

      vies_check
    rescue Valvat::RateLimitError, Valvat::Timeout, Valvat::BlockedError, Valvat::InvalidRequester => _e
      nil
    end

    def process_vies_tax(customer_vies)
      return "lago_eu_reverse_charge" unless organization_country_code.casecmp?(customer_vies[:country_code])

      standard_code = "lago_eu_#{organization_country_code.downcase}_standard"
      return standard_code if customer.zipcode.blank?
      return standard_code if applicable_tax_exceptions(country_code: customer_vies[:country_code]).blank?

      exception_code = applicable_tax_exceptions(country_code: customer_vies[:country_code]).first["name"].parameterize.underscore
      "lago_eu_#{customer_vies[:country_code].downcase}_exception_#{exception_code}"
    end

    def process_not_vies_tax
      return "lago_eu_#{organization_country_code.downcase}_standard" if customer.country.blank?
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

    def should_apply_eu_taxes?
      return false unless customer.organization.eu_tax_management
      return true if new_record

      non_existing_eu_taxes = customer.taxes.where("code ILIKE ?", "lago_eu%").none?

      non_existing_eu_taxes || tax_attributes_changed
    end
  end
end
