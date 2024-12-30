# frozen_string_literal: true

module Api
  module V1
    class InvoiceCustomSectionsController < Api::BaseController
      def create
        selected = params.dig(:invoice_custom_section, :selected) || false
        result = ::InvoiceCustomSections::CreateService.call(
          organization: current_organization, create_params: input_params, selected: selected
        )

        if result.success?
          render(
            json: ::V1::InvoiceCustomSectionSerializer.new(
              result.invoice_custom_section,
              root_name: "invoice_custom_section"
            )
          )
        else
          render_error_response(result)
        end
      end

      def update
        invoice_custom_section = InvoiceCustomSection.find_by(
          code: params[:code],
          organization_id: current_organization.id
        )
        selected = params.dig(:invoice_custom_section, :selected) || false

        result = ::InvoiceCustomSections::UpdateService.call(
          invoice_custom_section:,
          update_params: input_params.to_h.deep_symbolize_keys,
          selected:
        )

        if result.success?
          render(
            json: ::V1::InvoiceCustomSectionSerializer.new(
              result.invoice_custom_section,
              root_name: "invoice_custom_section"
            )
          )
        else
          render_error_response(result)
        end
      end

      def destroy
        result = ::InvoiceCustomSections::DestroyService.call(
          invoice_custom_section: current_organization.invoice_custom_sections.find_by(code: params[:code])
        )

        if result.success?
          render(
            json: ::V1::InvoiceCustomSectionSerializer.new(
              result.invoice_custom_section,
              root_name: "invoice_custom_section"
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        metric = current_organization.invoice_custom_sections.find_by(
          code: params[:code]
        )

        return not_found_error(resource: "invoice_custom_section") unless metric

        render(
          json: ::V1::InvoiceCustomSectionSerializer.new(
            metric,
            root_name: "invoice_custom_section"
          )
        )
      end

      def index
        result = InvoiceCustomSectionsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          }
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.invoice_custom_sections,
              ::V1::InvoiceCustomSectionSerializer,
              collection_name: "invoice_custom_sections",
              meta: pagination_metadata(result.invoice_custom_sections)
            )
          )
        else
          render_error_response(result)
        end
      end

      private

      def input_params
        params.require(:invoice_custom_section).permit(
          :code,
          :description,
          :details,
          :display_name,
          :name
        )
      end

      def resource_name
        'invoice_custom_section'
      end
    end
  end
end
