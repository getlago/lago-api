# frozen_string_literal: true

module Clock
  class TerminateCouponsJob < ApplicationJob
    include SentryCronConcern

    queue_as "clock"

    def perform
      Coupons::TerminateService.terminate_all_expired
    end
  end
end
