# frozen_string_literal: true

module RecurringAggregationSnapshots
  # Snapshots of the product slice a contract's rate card prices: a single bucket, which marks its own periods.
  ContractKey = Data.define(:contract, :product, :product_filter) do
    def model
      ContractRecurringAggregationSnapshot
    end

    delegate :organization_id, to: :contract

    def snapshots
      model.where(organization_id:, contract_id: contract.id, product_id: product.id, product_filter_id: product_filter&.id)
    end

    def bucket_ids(_filter_ids)
      [product_filter&.id]
    end

    def marker_bucket_id
      product_filter&.id
    end

    # Another filter's rows would sit outside the rows this key locks, replaces and prunes
    def bucket_id(filter)
      raise ArgumentError, "bucket outside the contract key" unless filter&.id == product_filter&.id

      product_filter&.id
    end

    def row_attributes
      {organization_id:, contract_id: contract.id, product_id: product.id, billable_metric_id: product.billable_metric_id}
    end

    def lock_key(to_datetime)
      "contract-recurring-aggregation-snapshot-#{contract.id}-#{product.id}-#{product_filter&.id}-#{to_datetime.iso8601(6)}"
    end

    def filters_changed_since?(watermark)
      model.filters_changed_since?(organization_id:, contract_id: contract.id, product_id: product.id, watermark:)
    end

    # A replacement contract has no link to its predecessor yet: it full scans once.
    def previous_period(**)
      nil
    end
  end
end
