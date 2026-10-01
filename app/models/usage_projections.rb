# frozen_string_literal: true

class UsageProjections
  ProjectedFees = Data.define(:fees, :projections) do
    delegate :wrap, to: :projections

    def projection
      projections.for(fees)
    end
  end

  def initialize(projections_by_fee)
    @projections_by_fee = projections_by_fee
  end

  def for(fees)
    fees.sum(UsageProjection.zero) { |fee| projections_by_fee.fetch(fee) }
  end

  def wrap(fees)
    ProjectedFees.new(fees:, projections: self)
  end

  private

  attr_reader :projections_by_fee
end
