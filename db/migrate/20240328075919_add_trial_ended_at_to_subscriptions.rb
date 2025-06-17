# frozen_string_literal: true

class AddTrialEndedAtToSubscriptions < ActiveRecord::Migration[7.0]
  def change
    add_column :subscriptions, :trial_ended_at, :datetime
  end
end
