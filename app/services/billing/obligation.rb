# frozen_string_literal: true

module Billing
  Obligation = Data.define(:cycle, :segments, :billing_at)
end
