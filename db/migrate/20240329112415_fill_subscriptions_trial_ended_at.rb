# frozen_string_literal: true

class FillSubscriptionsTrialEndedAt < ActiveRecord::Migration[7.0]
  class Subscription < ApplicationRecord
    belongs_to :customer
    belongs_to :plan

    # NOTE: We reimplement the logic from Subscription#initial_started_at  differently to avoid N+1 queries
    #       eager loading subscription.customer.subscriptions is not enough.
    def initial_started_at
      customer.subscriptions.select do |s|
        s.external_id == external_id && s.started_at.present?
      end.min_by(&:started_at)&.started_at || subscription_at
    end
  end

  class Customer < ApplicationRecord
    has_many :subscriptions
  end

  class Plan < ApplicationRecord
    has_many :subscriptions
  end

  def up
    Subscription
      .joins(:plan)
      .where(trial_ended_at: nil)
      .where.not(plans: { trial_period: nil })
      .includes(:plan, customer: :subscriptions)
      .find_each do |subscription|
        trial_ended_at = subscription.initial_started_at + subscription.plan.trial_period.days

        next if trial_ended_at.to_date >= Time.zone.today

        subscription.update(trial_ended_at:)
      end
  end

  def down
  end
end
