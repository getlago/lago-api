# frozen_string_literal: true

module Api
  module V1
    class CustomersController < Api::BaseController
      def create
        service = Customers::CreateService.new
        result = service.create_from_api(
          organization: current_organization,
          params: create_params,
        )

        if result.success?
          render(
            json: ::V1::CustomerSerializer.new(
              result.customer,
              root_name: 'customer',
            ),
          )
        else
          render_error_response(result)
        end
      end

      def current_usage
        service = Invoices::CustomerUsageService
          .new(
            nil,
            customer_id: params[:customer_external_id],
            subscription_id: params[:external_subscription_id],
            organization_id: current_organization.id,
          )
        result = service.usage

        if result.success?
          render(
            json: ::V1::CustomerUsageSerializer.new(
              result.usage,
              root_name: 'customer_usage',
              includes: %i[charges_usage],
            ),
          )
        else
          render_error_response(result)
        end
      end

      def index
        customers = current_organization.customers
          .page(params[:page])
          .per(params[:per_page] || PER_PAGE)

        render(
          json: ::CollectionSerializer.new(
            customers,
            ::V1::CustomerSerializer,
            collection_name: 'customers',
            meta: pagination_metadata(customers),
          ),
        )
      end

      def show
        customer = current_organization.customers.find_by(external_id: params[:external_id])

        return not_found_error(resource: 'customer') unless customer

        render(
          json: ::V1::CustomerSerializer.new(
            customer,
            root_name: 'customer',
          ),
        )
      end

      private

      def create_params
        params.require(:customer).permit(
          :external_id,
          :name,
          :country,
          :address_line1,
          :address_line2,
          :state,
          :zipcode,
          :email,
          :city,
          :url,
          :phone,
          :logo_url,
          :legal_name,
          :legal_number,
          :vat_rate,
          :currency,
          billing_configuration: [
            :payment_provider,
            :provider_customer_id,
            :sync,
            :gocardless_mandate_id,
            :sync_with_provider,
          ],
        )
      end
    end
  end
end
