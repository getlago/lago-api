# frozen_string_literal: true

module Api
  module V1
    class BillingEntitiesController < Api::BaseController
      def create
        result = BillingEntities::CreateService.call(
          params: input_params.to_h, organization: current_organization
        )

        if result.success?
          render_billing_entity(result.billing_entity)
        else
          render_error_response(result)
        end
      end

      def update
        billing_entity = current_organization.billing_entities.find_by(code: params[:code])

        result = BillingEntities::UpdateService.call(
          billing_entity:,
          params: input_params.to_h
        )

        if result.success?
          render_billing_entity(result.billing_entity)
        else
          render_error_response(result)
        end
      end

      def show
        billing_entity = current_organization.billing_entities.find_by(
          code: params[:code]
        )
        return not_found_error(resource: "billing_entity") unless billing_entity

        render_billing_entity(billing_entity)
      end

      def index
        entities = current_organization.billing_entities

        render(
          json: ::CollectionSerializer.new(
            entities,
            ::V1::BillingEntitySerializer,
            collection_name: "billing_entities"
          )
        )
      end

      private

      def input_params
        params.require(:billing_entity).permit(
          :name,
          :code,
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
          :document_numbering,
          :document_number_prefix,
          :finalize_zero_amount_invoice,
          email_settings: [],
          billing_configuration: [
            :invoice_footer,
            :invoice_grace_period,
            :document_locale
          ]
        )
      end

      def render_billing_entity(billing_entity)
        render(
          json: ::V1::BillingEntitySerializer.new(
            billing_entity,
            root_name: "billing_entity",
            includes: %i[taxes invoice_custom_sections]
          )
        )
      end

      def resource_name
        'billing_entity'
      end
    end
  end
end
