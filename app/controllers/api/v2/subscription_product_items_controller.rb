# frozen_string_literal: true

module Api
  module V2
    class SubscriptionProductItemsController < Api::BaseController
      def create
        subscription = current_organization.subscriptions.find_by(
          external_id: create_params[:subscription_external_id], status: :active
        )
        return not_found_error(resource: "subscription") unless subscription

        product_item = current_organization.product_items.find_by(id: create_params[:product_item_id])
        return not_found_error(resource: "product_item") unless product_item

        result = ::SubscriptionProductItems::CreateService.call(
          subscription:,
          product_item:,
          started_at: create_params[:started_at] || subscription.started_at,
          billing_anchor_date: create_params[:billing_anchor_date],
          units: create_params[:units]
        )

        if result.success?
          render_subscription_product_item(result.subscription_product_item)
        else
          render_error_response(result)
        end
      end

      private

      def create_params
        params.require(:subscription_product_item).permit(
          :subscription_external_id,
          :product_item_id,
          :started_at,
          :billing_anchor_date,
          :units
        )
      end

      def render_subscription_product_item(subscription_product_item)
        render(json: ::V1::SubscriptionProductItemSerializer.new(subscription_product_item, root_name: "subscription_product_item"))
      end

      def resource_name
        "subscription"
      end
    end
  end
end
