# frozen_string_literal: true

module Api
  module V2
    class CustomersController < Api::V2::BaseController
      PRELOADS = %i[
        organization
        billing_entity
        stripe_customer
        gocardless_customer
        cashfree_customer
        adyen_customer
        flutterwave_customer
        moneyhash_customer
      ].freeze

      cursor_paginated_index(Customer)
      serializable_with ::V2::CustomerSerializer, serializer_options: {include_shipping_address: true}

      def index
        filters = index_filters.to_h.symbolize_keys
        search_term = filters.delete(:search_term)
        billing_entity_codes = filters.delete(:billing_entity_codes)

        if billing_entity_codes.present?
          billing_entity_ids = current_organization.all_billing_entities.where(code: billing_entity_codes).ids

          if billing_entity_ids.size != billing_entity_codes.uniq.size
            return not_found_error(resource: "billing_entity")
          end

          filters[:billing_entity_ids] = billing_entity_ids
        end

        result = ::CustomersQuery.call(
          organization: current_organization,
          pagination: cursor,
          search_term:,
          filters:
        )

        if result.success?
          render_customers(result.customers.preload(PRELOADS))
        else
          render_error_response(result)
        end
      end

      def show
        customer = current_organization.customers.find_by(external_id: params[:external_id])
        return not_found_error(resource: "customer") unless customer

        render_customer(customer)
      end

      def create
        result = ::Customers::UpsertFromApiService.call(
          organization: current_organization,
          params: input_params,
          mode: :create
        )

        if result.success?
          render_customer(result.customer)
        else
          render_error_response(result)
        end
      end

      def update
        result = ::Customers::UpsertFromApiService.call(
          organization: current_organization,
          params: input_params,
          mode: :update,
          external_id: params[:external_id]
        )

        if result.success?
          render_customer(result.customer)
        else
          render_error_response(result)
        end
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

      private

      def customer_payload
        payload = params.require(:customer)
        unless payload.is_a?(ActionController::Parameters)
          raise ActionController::ParameterMissing, :customer
        end

        %i[billing_configuration shipping_address].each do |key|
          if payload[key].is_a?(Array)
            raise ActionController::ParameterMissing, key
          end
        end

        payload
      end

      def input_params
        input = customer_payload.permit(
          :external_id,
          :name,
          :firstname,
          :lastname,
          :customer_type,
          :account_type,
          :email,
          :phone,
          :url,
          :logo_url,
          :address_line1,
          :address_line2,
          :city,
          :state,
          :zipcode,
          :country,
          :legal_name,
          :legal_number,
          :tax_identification_number,
          :currency,
          :timezone,
          :finalize_zero_amount_invoice,
          :skip_invoice_custom_sections,
          :external_salesforce_id,
          :billing_entity_code,
          billing_configuration: [
            :invoice_grace_period,
            :subscription_invoice_issuing_date_anchor,
            :subscription_invoice_issuing_date_adjustment,
            :payment_provider,
            :payment_provider_code,
            :provider_customer_id,
            :sync,
            :sync_with_provider,
            :document_locale,
            provider_payment_methods: []
          ],
          shipping_address: [
            :address_line1,
            :address_line2,
            :city,
            :zipcode,
            :state,
            :country
          ],
          integration_customers: [[
            :id,
            :code,
            :external_customer_id,
            :integration_type,
            :integration_code,
            :subsidiary_id,
            :sync_with_provider,
            :targeted_object
          ]],
          metadata: [[
            :id,
            :key,
            :value,
            :display_on_invoice
          ]],
          tax_codes: [],
          invoice_custom_section_codes: []
        ).to_h.deep_symbolize_keys

        normalize_metadata!(input[:metadata])
        input
      end

      def normalize_metadata!(metadata)
        metadata&.each do |entry|
          if entry.key?(:display_on_invoice)
            entry[:display_in_invoice] = entry.delete(:display_on_invoice)
          end
        end
      end

      def index_filters
        params.permit(
          :search_term,
          :external_id,
          :has_tax_identification_number,
          :has_customer_type,
          :customer_type,
          currencies: [],
          countries: [],
          states: [],
          zipcodes: [],
          billing_entity_codes: [],
          account_type: [],
          metadata: {}
        )
      end

      def resource_name
        "customer"
      end
    end
  end
end
