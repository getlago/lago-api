# frozen_string_literal: true

module Utils
  class SubscriptionRenewalService < BaseService
    def self.is_renewal_by_timebased_event?(subscription)
      charges = subscription.plan.charges

      charges.count == 1 && charges.first.charge_model.to_sym == :timebased
    end
  end
end
