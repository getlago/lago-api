# frozen_string_literal: true

module PaymentProviders
  module Moneyhash
    class HandleEventJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      def perform(organization:, event_json:)
        result = ::PaymentProviders::MoneyhashService.new.handle_event(organization:, event_json:)
        result.raise_if_error!
      end
    end
  end
end
