# frozen_string_literal: true

module Api
  module V1
    module Subscriptions
      class BaseController < Api::BaseController
        before_action :find_subscription

        private

        attr_reader :subscription

        def find_subscription
          @subscription = current_organization.subscriptions
            .order("terminated_at DESC NULLS FIRST, started_at DESC") # TODO: Confirm
            .find_by!(
              external_id: params[:subscription_external_id]
            )
        rescue ActiveRecord::RecordNotFound
          not_found_error(resource: "subscription")
        end
      end
    end
  end
end
