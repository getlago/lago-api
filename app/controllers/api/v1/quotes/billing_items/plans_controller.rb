# frozen_string_literal: true

module Api
  module V1
    module Quotes
      module BillingItems
        class PlansController < Api::BaseController
          def create
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::Plans::AddService.call(quote:, params: create_params.to_h)
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          def update
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::Plans::UpdateService.call(quote:, id: params[:id], params: update_params.to_h)
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          def destroy
            quote = current_organization.quotes.find_by(id: params[:quote_id])
            result = ::Quotes::BillingItems::Plans::RemoveService.call(quote:, id: params[:id])
            result.success? ? render_quote(result.quote) : render_error_response(result)
          end

          private

          def create_params
            extract_plan_params(params.require(:plan))
          end

          def update_params
            extract_plan_params(params.require(:plan))
          end

          def extract_plan_params(plan_params)
            permitted = plan_params.permit(
              :plan_id,
              :plan_name,
              :plan_code,
              :plan_description,
              :position,
              :subscription_external_id
            )
            permitted[:plan_overrides] = plan_params[:plan_overrides]&.to_unsafe_h
            permitted[:entitlements_overrides] = plan_params[:entitlements_overrides]&.to_unsafe_h
            permitted
          end

          def render_quote(quote)
            render(json: ::V1::QuoteSerializer.new(quote, root_name: "quote"))
          end

          def resource_name
            "quote"
          end
        end
      end
    end
  end
end
