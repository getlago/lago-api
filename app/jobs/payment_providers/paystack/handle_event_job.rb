# frozen_string_literal: true

module PaymentProviders
  module Paystack
    class HandleEventJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      def perform(organization_id, payment_provider_id, event_json)
        organization = Organization.find(organization_id)
        payment_provider = organization.paystack_payment_providers.find(payment_provider_id)

        PaymentProviders::Paystack::HandleEventService.call!(
          organization:,
          payment_provider:,
          event_json:
        )
      end
    end
  end
end
