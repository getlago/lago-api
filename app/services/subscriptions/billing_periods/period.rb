# frozen_string_literal: true

module Subscriptions
  module BillingPeriods
    # One materialized period. The only thing an engine adapter has to produce, so supporting the
    # product catalog later means adding an adapter rather than touching the writer.
    Period = Data.define(:scope_type, :scope_id, :period_from, :period_to)
  end
end
