# frozen_string_literal: true

module CustomerSnapshots
  class CreateService < BaseService
    Result = BaseResult[:customer_snapshot]
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result if invoice.customer_snapshot.present?

      snapshot_attributes = CustomerSnapshot::SNAPSHOTTED_ATTRIBUTES.each_with_object({}) do |attribute, hash|
        hash[attribute] = invoice.customer.public_send(attribute)
      end

      customer_snapshot = invoice.build_customer_snapshot(
        snapshot_attributes.merge(organization: invoice.organization)
      )
      customer_snapshot.save!

      result.customer_snapshot = customer_snapshot
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice
  end
end
