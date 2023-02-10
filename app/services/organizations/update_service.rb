# frozen_string_literal: true

module Organizations
  class UpdateService < BaseService
    def initialize(organization)
      @organization = organization

      super(nil)
    end

    def update(**args)
      billing_configuration = args[:billing_configuration]&.to_h || {}

      organization.vat_rate = billing_configuration[:vat_rate] if billing_configuration.key?(:vat_rate)
      organization.webhook_url = args[:webhook_url] if args.key?(:webhook_url)
      organization.legal_name = args[:legal_name] if args.key?(:legal_name)
      organization.legal_number = args[:legal_number] if args.key?(:legal_number)
      organization.email = args[:email] if args.key?(:email)
      organization.address_line1 = args[:address_line1] if args.key?(:address_line1)
      organization.address_line2 = args[:address_line2] if args.key?(:address_line2)
      organization.state = args[:state] if args.key?(:state)
      organization.zipcode = args[:zipcode] if args.key?(:zipcode)
      organization.city = args[:city] if args.key?(:city)
      organization.country = args[:country] if args.key?(:country)

      if billing_configuration.key?(:document_locale)
        organization.document_locale = billing_configuration[:document_locale]
      end

      if billing_configuration.key?(:invoice_footer)
        organization.invoice_footer = billing_configuration[:invoice_footer]
      end

      assign_premium_attributes(organization, args)

      if License.premium? && billing_configuration.key?(:invoice_grace_period)
        Organizations::UpdateInvoiceGracePeriodService.call(
          organization:,
          grace_period: billing_configuration[:invoice_grace_period],
        )
      end

      handle_base64_logo(args[:logo]) if args.key?(:logo)

      organization.save!

      result.organization = organization
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    def update_from_api(params:)
      organization.webhook_url = params[:webhook_url] if params.key?(:webhook_url)
      organization.country = params[:country] if params.key?(:country)
      organization.address_line1 = params[:address_line1] if params.key?(:address_line1)
      organization.address_line2 = params[:address_line2] if params.key?(:address_line2)
      organization.state = params[:state] if params.key?(:state)
      organization.zipcode = params[:zipcode] if params.key?(:zipcode)
      organization.email = params[:email] if params.key?(:email)
      organization.city = params[:city] if params.key?(:city)
      organization.legal_name = params[:legal_name] if params.key?(:legal_name)
      organization.legal_number = params[:legal_number] if params.key?(:legal_number)

      assign_premium_attributes(organization, params)

      if params.key?(:billing_configuration)
        billing = params[:billing_configuration]
        organization.invoice_footer = billing[:invoice_footer] if billing.key?(:invoice_footer)
        organization.vat_rate = billing[:vat_rate] if billing.key?(:vat_rate)

        if License.premium? && billing.key?(:invoice_grace_period)
          Organizations::UpdateInvoiceGracePeriodService.call(
            organization:,
            grace_period: billing[:invoice_grace_period],
          )
        end
      end

      organization.save!

      result.organization = organization
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :organization

    def assign_premium_attributes(organization, args)
      return unless License.premium?

      organization.timezone = args[:timezone] if args.key?(:timezone)
    end

    def handle_base64_logo(logo)
      return if logo.blank?

      base64_data = logo.split(',')
      data = base64_data.second
      decoded_base_64_data = Base64.decode64(data)

      # NOTE: data:image/png;base64, should give image/png content_type
      content_type = base64_data.first.split(';').first.split(':').second

      organization.logo.attach(
        io: StringIO.new(decoded_base_64_data),
        filename: 'logo',
        content_type: content_type,
      )
    end
  end
end
