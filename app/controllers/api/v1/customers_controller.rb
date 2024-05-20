# frozen_string_literal: true

module Api
  module V1
    class CustomersController < Api::BaseController
      def create
        service = ::Customers::CreateService.new
        result = service.create_from_api(
          organization: current_organization,
          params: create_params.to_h.deep_symbolize_keys,
        )

        if result.success?
          render_customer(result.customer)
        else
          render_error_response(result)
        end
      end

      def portal_url
        customer = current_organization.customers.find_by(external_id: params[:customer_external_id])

        result = ::CustomerPortal::GenerateUrlService.call(customer:)

        if result.success?
          render(
            json: {
              customer: {
                portal_url: result.url,
              },
            },
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
            includes: %i[taxes],
          ),
        )
      end

      def show
        customer = current_organization.customers.find_by(external_id: params[:external_id])

        return not_found_error(resource: 'customer') unless customer

        render_customer(customer)
      end

      def destroy
        customer = current_organization.customers.find_by(external_id: params[:external_id])
        result = ::Customers::DestroyService.call(customer:)

        if result.success?
          render_customer(result.customer)
        else
          render_error_response(result)
        end
      end

      def checkout_url
        customer = current_organization.customers.find_by(external_id: params[:customer_external_id])

        result = ::Customers::GenerateCheckoutUrlService.call(customer:)

        if result.success?
          render(
            json: ::V1::PaymentProviders::CustomerCheckoutSerializer.new(
              customer,
              root_name: 'customer',
              checkout_url: result.checkout_url,
            ),
          )
        else
          render_error_response(result)
        end
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
          :tax_identification_number,
          :currency,
          :timezone,
          :net_payment_term,
          :external_salesforce_id,
          integration_customer: [
            :external_customer_id,
            :integration_type,
            :integration_code,
            :subsidiary_id,
            :sync_with_provider,
          ],
          billing_configuration: [
            :invoice_grace_period,
            :payment_provider,
            :payment_provider_code,
            :provider_customer_id,
            :sync,
            :sync_with_provider,
            :document_locale,

            # NOTE(legacy): vat has been moved to tax model
            :vat_rate,
            provider_payment_methods: [],
          ],
          metadata: [
            :id,
            :key,
            :value,
            :display_in_invoice,
          ],
          tax_codes: [],
        )
      end

      def render_customer(customer)
        render(
          json: ::V1::CustomerSerializer.new(
            customer,
            root_name: 'customer',
            includes: %i[taxes integration_customers],
          ),
        )
      end
    end
  end
end
