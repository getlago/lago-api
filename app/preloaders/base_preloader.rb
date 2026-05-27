# frozen_string_literal: true

class BasePreloader
  def initialize(scope, *values)
    @scope = scope
    @values = values.empty? ? self.class::PRELOAD : values
  end

  def call
    values.each do |value|
      send("preload_#{value}")
    end

    scope
  end

  private

  attr_reader :scope, :values

  def scope_ids
    @scope_ids ||= scope.map(&:id).compact
  end

  def cache(records, value, preloaded)
    records.each do |record|
      record.preloader_cache[value] = preloaded[record.id] || 0
    end
  end
end
