# frozen_string_literal: true

module Clock
  class TerminateCouponsJob < ClockJob
    def perform
      Coupons::TerminateService.terminate_all_expired
    end
  end
end
