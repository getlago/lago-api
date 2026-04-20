# frozen_string_literal: true

module Api
  module V1
    class OrderFormsController < Api::BaseController
      before_action :ensure_feature_flag!

      def index
        result = OrderFormsQuery.call(
          organization: current_organization,
          pagination: {
            page: params[:page],
            limit: params[:per_page] || PER_PAGE
          },
          filters: index_filters,
          search_term: params[:search_term]
        )

        if result.success?
          render(
            json: ::CollectionSerializer.new(
              result.order_forms,
              ::V1::OrderFormSerializer,
              collection_name: "order_forms",
              meta: pagination_metadata(result.order_forms)
            )
          )
        else
          render_error_response(result)
        end
      end

      def show
        order_form = current_organization.order_forms.find_by(id: params[:id])
        return not_found_error(resource: "order_form") unless order_form

        render_order_form(order_form)
      end

      private

      def ensure_feature_flag!
        forbidden_error(code: "feature_not_available") unless current_organization.feature_flag_enabled?(:order_forms)
      end

      def index_filters
        {
          status: params[:status],
          customer_id: params[:customer_id],
          number: params[:number],
          quote_number: params[:quote_number],
          owner_id: params[:owner_id],
          created_at_from: params[:created_at_from],
          created_at_to: params[:created_at_to],
          expires_at_from: params[:expires_at_from],
          expires_at_to: params[:expires_at_to]
        }
      end

      def render_order_form(order_form)
        render(
          json: ::V1::OrderFormSerializer.new(order_form, root_name: "order_form")
        )
      end

      def resource_name
        "order_form"
      end
    end
  end
end
