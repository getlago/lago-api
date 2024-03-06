# frozen_string_literal: true

class TimebasedEvent < ApplicationRecord
  belongs_to :billable_metric, optional: true
  belongs_to :organization
  belongs_to :invoice, optional: true

  EVENT_TYPES = %i[
    subscription_renewal
    usage_time_started
  ].freeze

  enum event_type: EVENT_TYPES
end
