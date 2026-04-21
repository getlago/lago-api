# frozen_string_literal: true

module Subscriptions
  module ActivationRules
    module Payment
      class ResolveJob < ApplicationJob
        queue_as "default"

        def perform(subscription, invoice, payment_status)
          Payment::ResolveService.call!(subscription:, invoice:, payment_status:)
        end
      end
    end
  end
end
