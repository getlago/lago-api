# frozen_string_literal: true

module Webhooks
  module RateCards
    class DeletedService < Webhooks::BaseService
      private

      # Flat, the body this event has always sent: its rates are discarded with the card, so `rates`
      # would be empty and `active_rate` null, but `taxes` would list the taxes still linked to it.
      def object_serializer
        ::V2::RateCardSerializer.new(object, root_name: object_type, webhook: false)
      end

      def webhook_type
        "rate_card.deleted"
      end

      def object_type
        "rate_card"
      end
    end
  end
end
