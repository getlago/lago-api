# frozen_string_literal: true

module BillingSegments
  EMPTY_CYCLE_USAGE_TRACKER = Data.define do
    def apply_closing_values?(groups: []) = false
    def apply_carry_over? = false
    def carryover_variation? = false
    def empty? = true
  end.new
end
