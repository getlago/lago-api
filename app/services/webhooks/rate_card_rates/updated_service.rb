# frozen_string_literal: true

module Webhooks
  module RateCardRates
    class UpdatedService < Webhooks::BaseService
      private

      def object_serializer
        ::V2::RateCardRateSerializer.new(object, root_name: object_type, webhook: true)
      end

      def webhook_type
        "rate_card_rate.updated"
      end

      def object_type
        "rate_card_rate"
      end
    end
  end
end
