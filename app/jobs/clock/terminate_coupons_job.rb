# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Clock
  class TerminateCouponsJob < ClockJob
    def perform
      Coupons::TerminateService.terminate_all_expired
    end
  end
end
