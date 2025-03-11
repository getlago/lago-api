# frozen_string_literal: true

module BillingEntities
  class CreateService < BaseService
    Result = BaseResult[:billing_entity]

    def initialize(organization:, params:)
      @organization = organization
      @params = params
      super
    end

    def call
      return result.forbidden_failure! unless organization.can_create_billing_entity?

      billing_entity = organization.billing_entities.new(create_attributes)

      ActiveRecord::Base.transaction do
        billing_entity.invoice_footer = billing_config[:invoice_footer]
        billing_entity.document_locale = billing_config[:document_locale] if billing_config[:document_locale]

        handle_eu_tax_management(billing_entity)
        handle_base64_logo(billing_entity)

        if License.premium?
          # NOTE: multi entities is already a premium feature... so this is always true
          billing_entity.invoice_grace_period = billing_config[:invoice_grace_period] if billing_config[:invoice_grace_period]
          billing_entity.timezone = params[:timezone] if params[:timezone]
          billing_entity.email_settings = params[:email_settings] if params[:email_settings]
        end

        billing_entity.save!
      end

      track_billing_entity_created(billing_entity)

      result.billing_entity = billing_entity
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    rescue BaseService::FailedResult => e
      result.fail_with_error!(e)
    end

    private

    attr_reader :organization, :params

    def create_attributes
      @create_attributes ||= params.slice(
        *%I[
          address_line1
          address_line2
          city
          code
          country
          default_currency
          document_number_prefix
          document_numbering
          email
          finalize_zero_amount_invoice
          legal_name
          legal_number
          name
          net_payment_term
          state
          tax_identification_number
          vat_rate
          zipcode
        ]
      )
    end

    def billing_config
      @billing_config ||= params[:billing_configuration]&.to_h || {}
    end

    def handle_base64_logo(billing_entity)
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

    def handle_eu_tax_management(billing_entity)
      return if params[:eu_tax_management].blank?

      unless billing_entity.eu_vat_eligible?
        result.single_validation_failure!(error_code: "billing_entity_must_be_in_eu", field: :eu_tax_management)
          .raise_if_error!
      end

      # FIXME: update the service to rename the params use billing_entity instead of organization
      Taxes::AutoGenerateService.call(organization: billing_entity)

      billing_entity.eu_tax_management = params[:eu_tax_management]
    end

    def track_billing_entity_created(billing_entity)
      SegmentTrackJob.perform_later(
        membership_id: CurrentContext.membership,
        event: "billing_entity_created",
        properties: {
          billing_entity_code: billing_entity.code,
          billing_entity_name: billing_entity.name,
          organization_id: billing_entity.organization_id
        }
      )
    end
  end
end
