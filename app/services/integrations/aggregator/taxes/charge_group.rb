# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module ChargeGroup
        KEY_PREFIX = "charge_"

        def self.key(charge_id)
          "#{KEY_PREFIX}#{charge_id}"
        end

        def self.by_charge(records)
          records.group_by { |record| (yield record) || record.object_id }.values
        end
      end
    end
  end
end
