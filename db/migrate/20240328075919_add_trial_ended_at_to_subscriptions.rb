# frozen_string_literal: true

class AddTrialEndedAtToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :trial_ended_at, :datetime

    # TODO: We need to migrate all subscriptions that have ended their trial period
    # It's not too critical because the FreeTrialBillingService will only look at subscriptions
    # with trial ending TODAY. It will ignore subscriptions that have already ended their trial period.
  end
end
