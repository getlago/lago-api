# frozen_string_literal: true

module Api
  module V2
    class PlansController < Api::BaseController
      include Api::RequiresProductCatalog

      def index
        result = PlansQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: {pricing_type: "product_catalog"}
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.plans.includes(:applied_rate_cards),
              ::V2::PlanSerializer,
              collection_name: "plans",
              meta: pagination_metadata(result.plans)
            )
          )
        else
          render_error_response(result)
        end
      end

      def create
        result = ::Plans::CreateService.call(input_params.merge(organization_id: current_organization.id).to_h.deep_symbolize_keys)

        if result.success?
          render_plan(result.plan)
        else
          render_error_response(result)
        end
      end

      def update
        plan = current_organization.plans.parents.product_catalog.find_by(code: params[:code])
        result = ::Plans::UpdateService.call(plan:, params: input_params.to_h.deep_symbolize_keys)

        if result.success?
          render_plan(result.plan)
        else
          render_error_response(result)
        end
      end

      def show
        plan = current_organization.plans.parents.product_catalog.find_by(code: params[:code])
        return not_found_error(resource: "plan") unless plan

        render_plan(plan)
      end

      private

      def input_params
        permitted = params.require(:plan).permit(:name, :code, :description, :invoice_display_name, :currency)
        # v2 exposes amount_currency as `currency`; the column keeps the v1 name.
        permitted[:amount_currency] = permitted.delete(:currency) if permitted.key?(:currency)
        permitted
      end

      def render_error_response(error_result)
        error = error_result.error
        if error.is_a?(BaseService::ValidationFailure) && error.messages.key?(:amount_currency)
          messages = error.messages.except(:amount_currency).merge(currency: error.messages[:amount_currency])
          return validation_errors(errors: messages)
        end

        super
      end

      def render_plan(plan)
        render(json: ::V2::PlanSerializer.new(plan, root_name: "plan"))
      end

      def resource_name
        "plan"
      end
    end
  end
end
