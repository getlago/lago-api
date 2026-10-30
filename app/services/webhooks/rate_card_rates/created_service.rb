# frozen_string_literal: true

module Webhooks
  module RateCardRates
    class CreatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::RateCardRateSerializer.new(object, root_name: object_type)
      end

      def webhook_type
        "rate_card_rate.created"
      end

      def object_type
        "rate_card_rate"
      end
    end
  end
end
