# frozen_string_literal: true

module Api
  module V1
    module Subscriptions
      class FixedChargesController < BaseController
        def index
          render(
            json: ::CollectionSerializer.new(
              subscription.fixed_charges,
              ::V1::FixedChargeSerializer,
              collection_name: "fixed_charges",
              includes: %i[taxes]
            )
          )
        end

        private

        def resource_name
          "subscription"
        end
      end
    end
  end
end
