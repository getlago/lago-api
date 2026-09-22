# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      class BasePayload < Integrations::Aggregator::BasePayload
        private

        def mapped_item(fee)
          if fee.charge?
            billable_metric_item(fee)
          elsif fee.add_on_id.present?
            add_on_item(fee)
          elsif fee.fixed_charge?
            fixed_charge_item(fee)
          elsif fee.commitment?
            commitment_item
          elsif fee.subscription?
            subscription_item
          end
        end
      end
    end
  end
end
