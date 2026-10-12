# frozen_string_literal: true

module X402
  module Settlements
    class ReconcileJob < ApplicationJob
      queue_as do
        if ActiveModel::Type::Boolean.new.cast(ENV["SIDEKIQ_PAYMENTS"])
          :payments
        else
          :providers
        end
      end

      unique :until_executed, on_conflict: :log, lock_ttl: 10.minutes

      def perform(settlement)
        X402::Settlements::ReconcileService.call!(settlement:)
      end
    end
  end
end
