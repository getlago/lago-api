# frozen_string_literal: true

class BasePreloader
  def initialize(records, *scopes)
    @records = records
    @scopes = scopes.any? ? scopes : self.class::SCOPES
  end

  def call
    scopes.each do |scope|
      send("preload_#{scope}")
    end

    records
  end

  private

  attr_reader :records, :scopes

  def record_ids
    @record_ids ||= records.map(&:id).compact
  end

  def cache(records, value, preloaded, default: 0)
    records.each do |record|
      record.preloader_cache[value] = preloaded[record.id] || default
    end
  end
end
