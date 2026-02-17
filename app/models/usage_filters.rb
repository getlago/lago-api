# frozen_string_literal: true

class UsageFilters
  attr_reader :filter_by_charge, :filter_by_group, :skip_grouping, :full_usage

  def initialize(filter_by_charge: nil, filter_by_group: nil, skip_grouping: false, full_usage: false)
    @filter_by_charge = filter_by_charge
    @filter_by_group = filter_by_group&.transform_values { |v| Array(v) }
    @skip_grouping = skip_grouping
    @full_usage = full_usage
  end

  NONE = new.freeze
end
