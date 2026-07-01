# frozen_string_literal: true

module Clock
  class TerminateCouponsJob < ClockJob
    unique :until_executed, on_conflict: :log

    def perform
      Coupons::TerminateService.terminate_all_expired
    end
  end
end
