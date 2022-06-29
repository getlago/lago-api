# frozen_string_literal: true

module Organizations
  class UpdateService < BaseService
    def initialize(organization)
      @organization = organization

      super(nil)
    end

    def update(**args)
      organization.vat_rate = args[:vat_rate] if args.key?(:vat_rate)
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
      organization.invoice_footer = args[:invoice_footer] if args.key?(:invoice_footer)

      handle_base64_logo(args[:logo]) if args.key?(:logo)

      organization.save!

      result.organization = organization

      result
    rescue ActiveRecord::RecordInvalid => e
      result.fail_with_validations!(e.record)
    end

    private

    attr_reader :organization

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
