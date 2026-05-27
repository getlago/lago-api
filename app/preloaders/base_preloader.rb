# frozen_string_literal: true

class BasePreloader
  def initialize(scope, *preloads)
    @scope = scope
    @preloads = preloads.any? ? preloads : self.class::PRELOADS
  end

  def call
    preloads.each do |value|
      send("preload_#{value}")
    end

    scope
  end

  private

  attr_reader :scope, :preloads

  def scope_ids
    @scope_ids ||= scope.map(&:id).compact
  end

  def cache(records, value, preloaded, default: 0)
    records.each do |record|
      record.preloader_cache[value] = preloaded[record.id] || default
    end
  end
end
