# frozen_string_literal: true

module Customers
  class EuAutoTaxesService < BaseService
    include Customers::Concerns::EuTaxCodeResolver

    # tax_codes is the full list of taxes to apply on the customer: the requested ones with the EU tax code.
    Result = BaseResult[:tax_code, :tax_codes]

    B2B_ONLY_TERRITORY_COUNTRIES = %w[FR].freeze
    EU_TAX_CODE_PREFIX = "lago_eu"
    EU_TAX_EXEMPT_CODE = "lago_eu_tax_exempt"

    def initialize(customer:, new_record:, tax_attributes_changed:, tax_codes: nil)
      @customer = customer
      @new_record = new_record
      @tax_attributes_changed = tax_attributes_changed
      @tax_codes = tax_codes

      super
    end

    def call
      return result.not_allowed_failure!(code: "eu_tax_not_applicable") unless customer.billing_entity.eu_tax_management

      kept_tax_codes = custom_tax_codes_to_keep
      if kept_tax_codes
        delete_pending_vies_check_if_exists
        if tax_codes.nil? && kept_tax_codes.sort == customer_tax_codes.sort
          return result.not_allowed_failure!(code: "eu_tax_not_applicable")
        end

        result.tax_codes = kept_tax_codes
        return result
      end

      return result.not_allowed_failure!(code: "eu_tax_not_applicable") unless should_apply_eu_taxes?

      territory_tax_code = detect_special_territory
      if territory_tax_code
        assign_tax_code(territory_tax_code)
        delete_pending_vies_check_if_exists
        return result
      end

      if customer.tax_identification_number.present?
        schedule_async_vies_check
        return result.service_failure!(code: "vies_check_pending", message: "VIES check scheduled asynchronously")
      end

      assign_tax_code(process_not_vies_tax)
      delete_pending_vies_check_if_exists
      result
    end

    private

    attr_reader :customer, :tax_attributes_changed, :new_record, :tax_codes

    def assign_tax_code(tax_code)
      result.tax_code = tax_code
      result.tax_codes = ((tax_codes || []) + [tax_code]).uniq
    end

    # Custom taxes on a customer outside the EU without tax ID (e.g. a B2C VAT) replace the EU taxes.
    def custom_tax_codes_to_keep
      return unless outside_eu_without_tax_id?

      if tax_codes.nil?
        # An EU rate left from a previous country must still be replaced by the exemption.
        current_codes = customer_tax_codes - [EU_TAX_EXEMPT_CODE]
        current_codes if current_codes.any? && current_codes.none? { |code| eu_tax_code?(code) }
      else
        requested_codes = tax_codes.reject { |code| eu_tax_code?(code) }
        requested_codes if requested_codes.any?(&:present?)
      end
    end

    def outside_eu_without_tax_id?
      customer.tax_identification_number.blank? &&
        customer.country.present? &&
        eu_countries_code.exclude?(customer.country.upcase)
    end

    def eu_tax_code?(code)
      code.to_s.downcase.start_with?(EU_TAX_CODE_PREFIX)
    end

    def detect_special_territory
      country_code = customer.country&.upcase
      return if country_code.blank? || customer.zipcode.blank?

      tax_exception = find_territory_tax_exception(country_code)
      return unless tax_exception

      territory_tax_code(country_code, tax_exception)
    end

    def find_territory_tax_exception(country_code)
      return unless eu_countries_code.include?(country_code)

      tax_exceptions = LagoEuVat::Rate.country_rates(country_code:)[:exceptions]
      return if tax_exceptions.blank?

      normalized_zip = customer.zipcode.gsub(/\s/, "")
      tax_exceptions.find { |tax_exception| normalized_zip.match?(tax_exception["postcode"]) }
    end

    def territory_tax_code(country_code, tax_exception)
      return if B2B_ONLY_TERRITORY_COUNTRIES.include?(country_code) && !is_b2b?

      exception_code = tax_exception["name"].parameterize.underscore
      "lago_eu_#{country_code.downcase}_exception_#{exception_code}"
    end

    def is_b2b?
      customer.tax_identification_number.present? && is_valid_vat_number?(customer.tax_identification_number)
    end

    def should_apply_eu_taxes?
      return true if new_record

      non_existing_eu_taxes = customer_tax_codes.none? { |code| eu_tax_code?(code) }

      non_existing_eu_taxes || tax_attributes_changed
    end

    def customer_tax_codes
      @customer_tax_codes ||= customer.taxes.pluck(:code)
    end

    def schedule_async_vies_check
      PendingViesCheck.find_or_initialize_by(customer:).update!(
        organization: customer.organization,
        billing_entity: customer.billing_entity,
        tax_identification_number: customer.tax_identification_number,
        attempts_count: 0,
        last_attempt_at: nil,
        last_error_type: nil,
        last_error_message: nil
      )

      Customers::ViesCheckJob.perform_after_commit(customer)
    end

    def delete_pending_vies_check_if_exists
      customer.pending_vies_check&.destroy!
    end
  end
end
