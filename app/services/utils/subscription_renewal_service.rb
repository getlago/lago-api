# frozen_string_literal: true

module Utils
  class SubscriptionRenewalService < BaseService
    def self.is_renewal_by_timebased_event?(subscription)
      renewal_charge = subscription
        .plan
        .charges
        .where(charge_model: :timebased)

      renewal_charge.count == 1
    end
  end
end
