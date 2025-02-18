# frozen_string_literal: true

module PaymentProviders
  module Adyen
    class HandleEventJob < ApplicationJob
      queue_as "providers"

      def perform(organization:, event_json:)
        PaymentProviders::Adyen::HandleEventService.call!(organization:, event_json:)
      end
    end
  end
end
