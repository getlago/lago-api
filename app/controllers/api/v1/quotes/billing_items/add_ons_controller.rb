# frozen_string_literal: true

module Api
  module V1
    module Quotes
      module BillingItems
        class AddOnsController < Api::BaseController
          def create
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::AddOns::AddService.call(quote:, params: create_params.to_h)
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          def update
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::AddOns::UpdateService.call(quote:, id: params[:id], params: update_params.to_h)
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          def destroy
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::AddOns::RemoveService.call(quote:, id: params[:id])
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          private

          def create_params
            extract_add_on_params(params.require(:add_on))
          end

          def update_params
            extract_add_on_params(params.require(:add_on))
          end

          def extract_add_on_params(add_on_params)
            permitted = add_on_params.permit(
              :add_on_id,
              :name,
              :description,
              :units,
              :amount_cents,
              :invoice_display_name,
              :service_from_date,
              :service_to_date,
              :position
            )
            permitted[:add_on_overrides] = add_on_params[:add_on_overrides]&.to_unsafe_h
            permitted
          end

          def render_quote(quote)
            render(json: ::V1::QuoteSerializer.new(quote, root_name: "quote").serialize)
          end

          def resource_name
            "quote"
          end
        end
      end
    end
  end
end
