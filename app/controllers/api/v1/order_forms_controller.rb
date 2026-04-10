# frozen_string_literal: true

module Api
  module V1
    class OrderFormsController < Api::BaseController
      include OrderFormIndex

      def index
        order_form_index
      end

      def show
        order_form = current_organization.order_forms.find_by(id: params[:id])
        return not_found_error(resource: "order_form") unless order_form

        render_order_form(order_form)
      end

      private

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
