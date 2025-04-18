# frozen_string_literal: true

module UsageMonitoring
  class ChargeUsageAmountAlert < Alert
    def find_value(thing_that_has_values_in_it)
      thing_that_has_values_in_it.fees.find { |fee| fee.charge_id == charge_id }.amount_cents
    end
  end
end
