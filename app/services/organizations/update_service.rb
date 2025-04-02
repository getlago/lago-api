# frozen_string_literal: true

module Organizations
  class UpdateService < BaseService
    Result = BaseResult[:organization]

    def initialize(organization:, params:)
      @organization = organization
      @params = params

      super(nil)
    end

    def call
      organization.email = params[:email] if params.key?(:email)
      organization.legal_name = params[:legal_name] if params.key?(:legal_name)
      organization.legal_number = params[:legal_number] if params.key?(:legal_number)
      if params.key?(:tax_identification_number)
        organization.tax_identification_number = params[:tax_identification_number]
      end
      organization.address_line1 = params[:address_line1] if params.key?(:address_line1)
      organization.address_line2 = params[:address_line2] if params.key?(:address_line2)
      organization.zipcode = params[:zipcode] if params.key?(:zipcode)
      organization.city = params[:city] if params.key?(:city)
      organization.state = params[:state] if params.key?(:state)
      organization.country = params[:country]&.upcase if params.key?(:country)
      organization.default_currency = params[:default_currency]&.upcase if params.key?(:default_currency)
      organization.document_number_prefix = params[:document_number_prefix] if params.key?(:document_number_prefix)
      organization.finalize_zero_amount_invoice = params[:finalize_zero_amount_invoice] if params.key?(:finalize_zero_amount_invoice)

      billing = params[:billing_configuration]&.to_h || {}
      organization.invoice_footer = billing[:invoice_footer] if billing.key?(:invoice_footer)
      organization.document_locale = billing[:document_locale] if billing.key?(:document_locale)

      ActiveRecord::Base.transaction do
        # NOTE: handle eu tax management for organization
        handle_eu_tax_management(params[:eu_tax_management]) if params.key?(:eu_tax_management)

        if params.key?(:webhook_url)
          webhook_endpoint = organization.webhook_endpoints.first_or_initialize
          webhook_endpoint.update!(webhook_url: params[:webhook_url])
        end

        if License.premium? && billing.key?(:invoice_grace_period)
          Organizations::UpdateInvoiceGracePeriodService.call(
            organization:,
            grace_period: billing[:invoice_grace_period]
          )
        end

        if params.key?(:net_payment_term)
          # note: this service only assigns new net_payment_term to the organization but doesn't save it
          Organizations::UpdateInvoicePaymentDueDateService.call(
            organization:,
            net_payment_term: params[:net_payment_term]
          )
        end

        if params.key?(:document_numbering)
          Organizations::UpdateInvoiceNumberingService.call(
            organization:,
            document_numbering: params[:document_numbering]
          )
        end

        assign_premium_attributes
        handle_base64_logo if params.key?(:logo)

        organization.save!
        update_billing_entity_result =
          BillingEntities::UpdateService.call(billing_entity: organization.default_billing_entity, params: params)
        update_billing_entity_result.raise_if_error!
      end

      ApiKeys::CacheService.expire_all_cache(organization)

      result.organization = organization
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue ArgumentError => e
      result.single_validation_failure!(error_code: e.message)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :organization, :params

    def assign_premium_attributes
      return unless License.premium?

      organization.timezone = params[:timezone] if params.key?(:timezone)
      organization.email_settings = params[:email_settings] if params.key?(:email_settings)
    end

    def handle_base64_logo
      return if params[:logo].blank?

      base64_data = params[:logo].split(",")
      data = base64_data.second
      decoded_base_64_data = Base64.decode64(data)

      # NOTE: data:image/png;base64, should give image/png content_type
      content_type = base64_data.first.split(";").first.split(":").second

      organization.logo.attach(
        io: StringIO.new(decoded_base_64_data),
        filename: "logo",
        content_type:
      )
    end

    def handle_eu_tax_management(eu_tax_management)
      trying_to_enable_eu_tax_management = params[:eu_tax_management] && !organization.eu_tax_management
      if !organization.eu_vat_eligible? && trying_to_enable_eu_tax_management
        result.single_validation_failure!(error_code: "org_must_be_in_eu", field: :eu_tax_management)
          .raise_if_error!
      end

      # NOTE: even if the organization had eu tax management, we call this service again, it uses an upsert for taxes.
      Taxes::AutoGenerateService.new(organization:).call if eu_tax_management

      organization.eu_tax_management = eu_tax_management
    end
  end
end
