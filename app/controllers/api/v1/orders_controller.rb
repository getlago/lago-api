# frozen_string_literal: true

module Api
  module V1
    class OrdersController < Api::BaseController
      include OrderIndex

      def index
        order_index
      end

      def show
        order = current_organization.orders.find_by(id: params[:id])
        return not_found_error(resource: "order") unless order

        render_order(order)
      end

      private

      def render_order(order)
        render(
          json: ::V1::OrderSerializer.new(order, root_name: "order")
        )
      end

      def resource_name
        "order"
      end
    end
  end
end
