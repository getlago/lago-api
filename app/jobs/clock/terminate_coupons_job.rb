# frozen_string_literal: true

module Clock
  class TerminateCouponsJob < ApplicationJob
    include SentryCronConcern

    queue_as do
      if ActiveModel::Type::Boolean.new.cast(ENV['SIDEKIQ_CLOCK'])
        :clock
      else
        :default
      end
    end

    def perform
      Coupons::TerminateService.terminate_all_expired
    end
  end
end
