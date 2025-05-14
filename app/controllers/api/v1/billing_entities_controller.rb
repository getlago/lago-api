# frozen_string_literal: true

module Api
  module V1
    class BillingEntitiesController < Api::BaseController
      def index
        render(
          json: ::CollectionSerializer.new(
            current_organization.billing_entities,
            ::V1::BillingEntitySerializer,
            collection_name: "billing_entities"
          )
        )
      end

      def show
        entity = BillingEntity.find_by(code: params[:code], organization: current_organization)

        return not_found_error(resource: "billing_entity") if entity.blank?

        render(
          json: ::V1::BillingEntitySerializer.new(entity, root_name: "billing_entity", includes: [:taxes])
        )
      end

      def update
        entity = BillingEntity.find_by(code: params[:code], organization: current_organization)
        return not_found_error(resource: "billing_entity") if entity.blank?

        result = BillingEntities::UpdateService.call(billing_entity: entity, params: update_params)

        if result.success?
          render(
            json: ::V1::BillingEntitySerializer.new(
              result.billing_entity,
              root_name: "billing_entity",
              includes: [:taxes]
            )
          )
        else
          render_error_response(result)
        end
      end

      def manage_taxes
        entity = BillingEntity.find_by(code: params[:code], organization: current_organization)
        return not_found_error(resource: "billing_entity") if entity.blank?

        result = BillingEntities::Taxes::ManageTaxesService.call(billing_entity: entity, tax_codes: params[:tax_codes])

        if result.success?
          render(json: ::V1::BillingEntitySerializer.new(entity, root_name: "billing_entity"))
        else
          render_error_response(result)
        end
      end

      private

      def update_params
        params.require(:billing_entity).permit(
          :name,
          :email,
          :legal_name,
          :legal_number,
          :tax_identification_number,
          :address_line1,
          :address_line2,
          :city,
          :state,
          :zipcode,
          :country,
          :default_currency,
          :timezone,
          :document_numbering,
          :document_number_prefix,
          :finalize_zero_amount_invoice,
          :net_payment_term,
          :eu_tax_management,
          :logo,
          email_settings: [],
          billing_configuration: [
            :invoice_footer,
            :invoice_grace_period,
            :document_locale
          ]
        )
      end
    end
  end
end
