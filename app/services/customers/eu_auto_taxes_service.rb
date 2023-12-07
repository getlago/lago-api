# frozen_string_literal: true

require 'valvat'

module Customers
  class EuAutoTaxesService < BaseService
    def initialize(customer:)
      @customer = customer
      @organization_country_code = customer.organization_country_code

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
      Valvat.new(customer.tax_identification_number).exists?(detail: true)
    end

    def process_vies_tax(customer_vies)
      if organization_country_code == customer_vies.vat_country_code
        "lago_eu_#{organization_country_code.downcase}_standard"
      else
        'lago_eu_reverse_charge'
      end
    end

    def process_not_vies_tax
      return "lago_eu_#{organization_country_code.downcase}_standard" if customer.country_code.blank?

      if eu_countries_code.include?[customer.country_code.upcase]
        return "lago_eu_#{customer.country_code.downcase}_standard"
      end

      'lago_eu_tax_exempt'
    end
  end
end
