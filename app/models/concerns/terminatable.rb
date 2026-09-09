# frozen_string_literal: true

module Terminatable
  extend ActiveSupport::Concern

  def terminated_at?(timestamp)
    return false unless terminated?
    return false if terminated_at.nil? || timestamp.nil?

    # TODO: should be cleaned up to only use Time
    timestamp = timestamp.to_time if [Date, DateTime, String].include?(timestamp.class)
    timestamp = Time.zone.at(timestamp) if timestamp.is_a?(Integer)

    terminated_at.round <= timestamp.round
  end
end
