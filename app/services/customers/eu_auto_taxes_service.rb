# frozen_string_literal: true

module Customers
  class EuAutoTaxesService < BaseService
    Result = BaseResult[:tax_code]

    RETRY_DELAYS = [5.minutes, 5.minutes, 10.minutes, 20.minutes, 40.minutes].freeze
    MAX_RETRY_DELAY = 1.hour

    def initialize(customer:, new_record:, tax_attributes_changed:)
      @customer = customer
      @billing_country_code = customer.billing_entity.country
      @new_record = new_record
      @tax_attributes_changed = tax_attributes_changed

      super
    end

    def call
      return result.not_allowed_failure!(code: "eu_tax_not_applicable") unless should_apply_eu_taxes?

      vies_api_response = check_vies

      result.tax_code = if vies_api_response.present?
        process_vies_tax(vies_api_response)
      else
        process_not_vies_tax
      end

      if customer.tax_identification_number.present?
        after_commit do
          SendWebhookJob.perform_later("customer.vies_check", customer, vies_check: vies_api_response.presence || error_vies_check)
        end
      end

      delete_pending_vies_check_if_exists
      result
    rescue Valvat::RateLimitError, Valvat::Timeout, Valvat::BlockedError, Valvat::InvalidRequester,
      Valvat::ServiceUnavailable, Valvat::MemberStateUnavailable => e
      create_or_update_pending_vies_check(e)
      after_commit do
        SendWebhookJob.perform_later("customer.vies_check", customer, vies_check: error_vies_check.merge(error: e.message))
        RetryViesCheckJob.set(wait: retry_delay).perform_later(customer.id)
      end
      result.service_failure!(code: "vies_check_failed", message: e.message)
    end

    private

    attr_reader :customer, :billing_country_code, :tax_attributes_changed, :new_record

    def check_vies
      return nil if customer.tax_identification_number.blank?

      # Just errors extended from Valvat::Lookup are raised, while Maintenances are not.
      # https://github.com/yolk/valvat/blob/master/README.md#handling-of-maintenance-errors
      # Check the Unavailable sheet per UE country.
      # https://ec.europa.eu/taxation_customs/vies/#/help
      Valvat.new(customer.tax_identification_number).exists?(detail: true, raise_error: true)
    end

    def error_vies_check
      {
        valid: false,
        valid_format: is_valid_vat_number?(customer.tax_identification_number)
      }
    end

    def is_valid_vat_number?(vat_number)
      ::Valvat::Syntax.validate(vat_number)
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

    def should_apply_eu_taxes?
      return false unless customer.billing_entity.eu_tax_management
      return true if new_record

      non_existing_eu_taxes = customer.taxes.where("code ILIKE ?", "lago_eu%").none?

      non_existing_eu_taxes || tax_attributes_changed
    end

    def create_or_update_pending_vies_check(exception)
      pending_check = PendingViesCheck.find_or_initialize_by(customer:)
      pending_check.assign_attributes(
        organization: customer.organization,
        billing_entity: customer.billing_entity,
        tax_identification_number: customer.tax_identification_number,
        attempts_count: pending_check.attempts_count + 1,
        last_attempt_at: Time.current,
        last_error_type: PendingViesCheck.error_type_for(exception),
        last_error_message: exception.message
      )
      pending_check.save!
    end

    def delete_pending_vies_check_if_exists
      customer.pending_vies_check&.destroy!
    end

    def retry_delay
      attempts = customer.reload.pending_vies_check&.attempts_count.to_i
      RETRY_DELAYS[attempts] || MAX_RETRY_DELAY
    end
  end
end
