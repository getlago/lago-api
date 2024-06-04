# frozen_string_literal: true

module Clock
  class TerminateCouponsJob < ApplicationJob
    prepend SentryCronConcern

    queue_as 'clock'

    def perform(*)
      Coupons::TerminateService.new.terminate_all_expired
    end
  end
end
