# frozen_string_literal: true

module Api
  module V1
    class OrganizationsController < Api::BaseController
      def update
        service = Organizations::UpdateService.new(current_organization)
        result = service.update_from_api(params: input_params)

        if result.success?
          render(
            json: ::V1::OrganizationSerializer.new(
              result.organization,
              root_name: 'organization',
            ),
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.require(:organization).permit(
          :webhook_url,
          :vat_rate,
          :country,
          :address_line1,
          :address_line2,
          :state,
          :zipcode,
          :email,
          :city,
          :legal_name,
          :legal_number,
          :invoice_footer,
          :invoice_grace_period,
        )
      end
    end
  end
end
