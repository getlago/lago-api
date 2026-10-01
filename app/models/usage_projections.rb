# frozen_string_literal: true

class UsageProjections
  def initialize(projections_by_fee)
    @projections_by_fee = projections_by_fee
  end

  def for(fees)
    fees.sum(UsageProjection.zero) { |fee| projections_by_fee.fetch(fee) }
  end

  private

  attr_reader :projections_by_fee
end
