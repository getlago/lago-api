class TimebasedEvent < ApplicationRecord
  belongs_to :organization
  belongs_to :invoice, optional: true

  EVENT_TYPES = %i[
    :renew_subscription
  ].freeze

  enum event_type: EVENT_TYPES
end
