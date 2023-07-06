# frozen_string_literal: true

module Organizations
  class UpdateService < BaseService
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
      organization.country = params[:country] if params.key?(:country)

      billing = params[:billing_configuration]&.to_h || {}
      organization.invoice_footer = billing[:invoice_footer] if billing.key?(:invoice_footer)
      organization.document_locale = billing[:document_locale] if billing.key?(:document_locale)

      # NOTE(legacy): keep accepting vat_rate field temporary by converting it into tax rate
      handle_legacy_vat_rate(billing[:vat_rate]) if billing.key?(:vat_rate)

      if params.key?(:webhook_url)
        webhook_endpoint = organization.webhook_endpoints.first_or_initialize
        webhook_endpoint.update! webhook_url: params[:webhook_url]
      end

      if License.premium? && billing.key?(:invoice_grace_period)
        Organizations::UpdateInvoiceGracePeriodService.call(
          organization:,
          grace_period: billing[:invoice_grace_period],
        )
      end

      assign_premium_attributes
      handle_base64_logo if params.key?(:logo)

      organization.save!

      result.organization = organization
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
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

      base64_data = params[:logo].split(',')
      data = base64_data.second
      decoded_base_64_data = Base64.decode64(data)

      # NOTE: data:image/png;base64, should give image/png content_type
      content_type = base64_data.first.split(';').first.split(':').second

      organization.logo.attach(
        io: StringIO.new(decoded_base_64_data),
        filename: 'logo',
        content_type:,
      )
    end

    def handle_legacy_vat_rate(vat_rate)
      if organization.taxes.applied_to_organization.count > 1
        result.single_validation_failure!(field: :vat_rate, error_code: 'multiple_taxes')
          .raise_if_error!
      end

      # NOTE(legacy): Keep updating vat_rate until we remove the field
      organization.vat_rate = vat_rate

      current_tax = organization.taxes.applied_to_organization.first
      return if current_tax&.rate == vat_rate

      current_tax&.update!(applied_to_organization: false)
      return if vat_rate.zero?

      organization.taxes.create_with(
        rate: vat_rate,
        name: "Tax (#{vat_rate}%)",
        applied_to_organization: true,
      ).find_or_create_by!(code: "tax_#{vat_rate}")
    end
  end
end
