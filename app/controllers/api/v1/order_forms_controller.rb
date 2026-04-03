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

      def mark_as_signed
        order_form = current_organization.order_forms.find_by(id: params[:id])

        user = current_organization.memberships
          .active
          .find_by(user_id: mark_as_signed_params[:signed_by_user_id])
          &.user

        unless user
          return render_error_response(
            BaseService::Result.new.validation_failure!(errors: {signed_by_user_id: ["user_not_found"]})
          )
        end

        result = OrderForms::MarkAsSignedService.call(order_form:, user:)

        if result.success?
          render_order_form(result.order_form)
        else
          render_error_response(result)
        end
      end

      def void
        order_form = current_organization.order_forms.find_by(id: params[:id])
        result = OrderForms::VoidService.call(order_form:)

        if result.success?
          render_order_form(result.order_form)
        else
          render_error_response(result)
        end
      end

      private

      def mark_as_signed_params
        params.require(:order_form).permit(:signed_by_user_id)
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
