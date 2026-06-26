# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module BillableMetrics
  module Breakdown
    Item = Data.define(:date, :action, :amount, :duration, :total_duration)
  end
end
