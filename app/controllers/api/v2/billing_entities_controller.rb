# frozen_string_literal: true

module Api
  module V2
    class BillingEntitiesController < Api::V2::BaseController
      # REST names of the settings the shared services read from `billing_configuration`.
      BILLING_CONFIGURATION_FIELDS = {
        invoice_footer: :invoice_footer,
        invoice_grace_period: :invoice_grace_period,
        periodic_invoice_issuing_date_anchor: :subscription_invoice_issuing_date_anchor,
        periodic_invoice_issuing_date_adjustment: :subscription_invoice_issuing_date_adjustment,
        document_locale: :document_locale
      }.freeze

      cursor_paginated_index(BillingEntity)
      date_range_filtered_index(:created_at)
      serializable_with ::V2::BillingEntitySerializer

      def index
        result = ::BillingEntitiesQuery.call(organization: current_organization, pagination: cursor, filters: date_range_filters)

        if result.success?
          render_billing_entities(result.billing_entities.with_attached_logo.preload(organization: :default_billing_entity))
        else
          render_error_response(result)
        end
      end

      def show
        billing_entity = find_billing_entity
        return not_found_error(resource: "billing_entity") unless billing_entity

        render_billing_entity(billing_entity)
      end

      def create
        input = input_params
        validation = ::BillingEntities::ValidateApiInputService.call(organization: current_organization, params: input, require_code: true)
        return render_error_response(validation) unless validation.success?

        result = ::BillingEntities::CreateService.call(organization: current_organization, params: cast_boolean_fields(input))

        if result.success?
          render_billing_entity(result.billing_entity)
        else
          render_error_response(result)
        end
      end

      def update
        billing_entity = find_billing_entity
        return not_found_error(resource: "billing_entity") unless billing_entity

        input = input_params.except(:code)
        validation = ::BillingEntities::ValidateApiInputService.call(organization: current_organization, params: input)
        return render_error_response(validation) unless validation.success?

        result = ::BillingEntities::UpdateService.call(billing_entity:, params: cast_boolean_fields(input))

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
          *BILLING_CONFIGURATION_FIELDS.keys,
          email_settings: [],
          tax_codes: [],
          invoice_custom_section_codes: []
        ).to_h.deep_symbolize_keys

        # The shared write services still expect nested billing fields.
        input[:billing_configuration] = input.extract!(*BILLING_CONFIGURATION_FIELDS.keys).transform_keys(BILLING_CONFIGURATION_FIELDS)
        input
      end

      def cast_boolean_fields(input)
        booleans = input.slice(*::BillingEntities::ValidateApiInputService::BOOLEAN_FIELDS)
          .transform_values { ActiveModel::Type::Boolean.new.cast(it) }
        input.merge(booleans)
      end

      def find_billing_entity
        current_organization.all_billing_entities
          .order("archived_at DESC NULLS FIRST")
          .find_by(code: params[:code])
      end

      def resource_name
        "billing_entity"
      end
    end
  end
end
