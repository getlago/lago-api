# frozen_string_literal: true

module Api
  module V2
    class BillingEntitiesController < Api::V2::BaseController
      BILLING_CONFIGURATION_FIELDS = %i[
        invoice_footer
        invoice_grace_period
        subscription_invoice_issuing_date_anchor
        subscription_invoice_issuing_date_adjustment
        document_locale
      ].freeze

      cursor_paginated_index(BillingEntity)
      serializable_with ::V2::BillingEntitySerializer

      def index
        result = ::BillingEntitiesQuery.call(organization: current_organization, pagination: cursor)
        render_billing_entities(result.billing_entities.with_attached_logo.preload(organization: :default_billing_entity))
      end

      def show
        billing_entity = current_organization.all_billing_entities.find_by(code: params[:code])
        return not_found_error(resource: "billing_entity") unless billing_entity

        render_billing_entity(billing_entity)
      end

      def create
        input = input_params.except(:tax_codes, :invoice_custom_section_codes)
        validation = ::BillingEntities::ValidateApiInputService.call(params: input, require_code: true)
        return render_error_response(validation) unless validation.success?

        result = ::BillingEntities::CreateService.call(organization: current_organization, params: input)

        if result.success?
          render_billing_entity(result.billing_entity)
        else
          render_error_response(result)
        end
      end

      def update
        billing_entity = current_organization.all_billing_entities.find_by(code: params[:code])
        return not_found_error(resource: "billing_entity") unless billing_entity

        input = update_params
        validation = ::BillingEntities::ValidateApiInputService.call(params: input)
        return render_error_response(validation) unless validation.success?

        result = ::BillingEntities::UpdateService.call(billing_entity:, params: input)

        if result.success?
          render_billing_entity(result.billing_entity)
        else
          render_error_response(result)
        end
      end

      private

      def billing_entity_payload
        payload = params.require(:billing_entity)
        unless payload.is_a?(ActionController::Parameters)
          raise ActionController::ParameterMissing, :billing_entity
        end

        payload
      end

      def input_params
        input = billing_entity_payload.permit(
          :code,
          :name,
          :email,
          :phone,
          :logo,
          :address_line1,
          :address_line2,
          :city,
          :state,
          :zipcode,
          :country,
          :legal_name,
          :legal_number,
          :tax_identification_number,
          :default_currency,
          :timezone,
          :finalize_zero_amount_invoice,
          :document_numbering,
          :document_number_prefix,
          :eu_tax_management,
          :einvoicing,
          *BILLING_CONFIGURATION_FIELDS,
          email_settings: [],
          tax_codes: [],
          invoice_custom_section_codes: []
        ).to_h.deep_symbolize_keys

        if input.key?(:eu_tax_management)
          input[:eu_tax_management] = ActiveModel::Type::Boolean.new.cast(input[:eu_tax_management])
        end

        # The shared write services still expect nested billing fields.
        input[:billing_configuration] = input.extract!(*BILLING_CONFIGURATION_FIELDS)
        input
      end

      def update_params
        input = input_params.except(:code)

        if input.key?(:invoice_custom_section_codes)
          codes = input.delete(:invoice_custom_section_codes)
          input[:invoice_custom_section_ids] = current_organization.invoice_custom_sections.where(code: codes).ids
        end

        input
      end

      def resource_name
        "billing_entity"
      end
    end
  end
end
