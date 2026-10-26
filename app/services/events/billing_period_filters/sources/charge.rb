# frozen_string_literal: true

module Events
  module BillingPeriodFilters
    module Sources
      Charge = Data.define(:charge, :filter) do
        include FilterSource

        delegate :billable_metric, to: :charge

        delegate :target_key, to: :charge

        def with_filter(filter)
          self.class.new(charge:, filter:)
        end

        private

        def filter_owner
          charge
        end
      end
    end
  end
end
