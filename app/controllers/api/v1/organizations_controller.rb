# frozen_string_literal: true

module Api
  module V1
    class OrganizationsController < Api::V1::BaseController
      def show
        render(
          json: ::V1::OrganizationSerializer.new(
            current_organization,
            root_name: "organization",
            include: %i[taxes]
          )
        )
      end

      def update
        result = Organizations::UpdateService.call(organization: current_organization, params: input_params)

        if result.success?
          render(
            json: ::V1::OrganizationSerializer.new(
              result.organization,
              root_name: "organization",
              includes: %i[taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.require(:organization).permit(
          :country,
          :default_currency,
          :address_line1,
          :address_line2,
          :state,
          :zipcode,
          :email,
          :city,
          :legal_name,
          :legal_number,
          :net_payment_term,
          :tax_identification_number,
          :timezone,
          :webhook_url,
          :document_numbering,
          :document_number_prefix,
          :finalize_zero_amount_invoice,
          :document_url_expiration_days,
          :slug,
          email_settings: [],
          customer_portal_locked_fields: [],
          billing_configuration: [
            :invoice_footer,
            :invoice_grace_period,
            :document_locale
          ]
        )
      end

      def resource_name
        "organization"
      end
    end
  end
end
