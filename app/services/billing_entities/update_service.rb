# frozen_string_literal: true

module BillingEntities
  class UpdateService < BaseService
    Result = BaseResult[:billing_entity]

    def initialize(billing_entity:, params:)
      @billing_entity = billing_entity
      @params = params

      super(nil)
    end

    def call
      return result.not_found_failure!(resource: "billing_entity") unless billing_entity

      billing_entity.name = params[:name] if params.key?(:name)
      billing_entity.email = params[:email] if params.key?(:email)
      billing_entity.legal_name = params[:legal_name] if params.key?(:legal_name)
      billing_entity.legal_number = params[:legal_number] if params.key?(:legal_number)
      if params.key?(:tax_identification_number)
        billing_entity.tax_identification_number = params[:tax_identification_number]
      end
      billing_entity.address_line1 = params[:address_line1] if params.key?(:address_line1)
      billing_entity.address_line2 = params[:address_line2] if params.key?(:address_line2)
      billing_entity.zipcode = params[:zipcode] if params.key?(:zipcode)
      billing_entity.city = params[:city] if params.key?(:city)
      billing_entity.state = params[:state] if params.key?(:state)
      billing_entity.country = params[:country]&.upcase if params.key?(:country)
      billing_entity.default_currency = params[:default_currency]&.upcase if params.key?(:default_currency)

      if params.key?(:document_numbering)
        # TODO: remove when we do not support document_numbering per organization
        document_numbering = (params[:document_numbering] == "per_customer") ? "per_customer" : "per_billing_entity"

        BillingEntities::ChangeInvoiceNumberingService.call(
          billing_entity:,
          document_numbering:
        )
      end

      billing_entity.document_number_prefix = params[:document_number_prefix] if params.key?(:document_number_prefix)
      billing_entity.finalize_zero_amount_invoice = params[:finalize_zero_amount_invoice] if params.key?(:finalize_zero_amount_invoice)

      billing = params[:billing_configuration]&.to_h || {}
      billing_entity.invoice_footer = billing[:invoice_footer] if billing.key?(:invoice_footer)
      billing_entity.document_locale = billing[:document_locale] if billing.key?(:document_locale)

      handle_eu_tax_management if params.key?(:eu_tax_management)

      if License.premium? && billing.key?(:invoice_grace_period)
        BillingEntities::UpdateInvoiceGracePeriodService.call(
          billing_entity:,
          grace_period: billing[:invoice_grace_period]
        )
      end

      if params.key?(:net_payment_term)
        # note: this service only assigns new net_payment_term to the billing_entity but doesn't save it
        BillingEntities::UpdateInvoicePaymentDueDateService.call(
          billing_entity:,
          net_payment_term: params[:net_payment_term]
        )
      end

      if params.key?(:tax_codes)
        BillingEntities::Taxes::ManageTaxesService.call(billing_entity: entity, tax_codes: params[:tax_codes])
      end

      assign_premium_attributes
      handle_base64_logo if params.key?(:logo)

      billing_entity.save!

      result.billing_entity = billing_entity
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ArgumentError => e
      result.single_validation_failure!(error_code: e.message)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :billing_entity, :params

    def assign_premium_attributes
      return unless License.premium?

      billing_entity.timezone = params[:timezone] if params.key?(:timezone)
      billing_entity.email_settings = params[:email_settings] if params.key?(:email_settings)
    end

    def handle_base64_logo
      return if params[:logo].blank?

      base64_data = params[:logo].split(",")
      data = base64_data.second
      decoded_base_64_data = Base64.decode64(data)

      # NOTE: data:image/png;base64, should give image/png content_type
      content_type = base64_data.first.split(";").first.split(":").second

      billing_entity.logo.attach(
        io: StringIO.new(decoded_base_64_data),
        filename: "logo",
        content_type:
      )
    end

    def handle_eu_tax_management
      ChangeEuTaxManagementService.call!(
        billing_entity:,
        eu_tax_management: params[:eu_tax_management]
      )
    end
  end
end
