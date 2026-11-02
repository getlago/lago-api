# frozen_string_literal: true

module Customers
  module Metadata
    class UpdateService < BaseService
      Result = BaseResult[:customer]

      def initialize(customer:, params:)
        @customer = customer
        @params = params
        super
      end

      def call
        created_metadata_ids = []

        hash_metadata = params.map { |m| m.to_h.deep_symbolize_keys }
        hash_metadata.each_with_index do |payload_metadata, index|
          metadata = customer.metadata.find_by(id: payload_metadata[:id])
          payload_metadata[:display_in_invoice] = payload_metadata[:display_in_invoice] || false

          if metadata
            metadata.update!(payload_metadata)

            next
          end

          created_metadata = create_metadata(payload_metadata)
          created_metadata_ids.push(created_metadata.id)
        rescue ActiveRecord::RecordInvalid => e
          # Raised as the record error was, which the callers roll back on. v1 and GraphQL clients read
          # the errors under the fields of the entry.
          result.record_validation_failure!(record: e.record, v2_only: true) { BaseService::ValidationFailure.item_field(:metadata, index, it) }.raise_if_error!
        end

        # NOTE: Delete metadata that are no more linked to the customer
        sanitize_metadata(hash_metadata, created_metadata_ids)

        result.customer = customer
        result
      end

      private

      attr_reader :customer, :params

      def create_metadata(payload)
        customer.metadata.create!(
          organization_id: customer.organization_id,
          key: payload[:key],
          value: payload[:value],
          display_in_invoice: payload[:display_in_invoice]
        )
      end

      def sanitize_metadata(args_metadata, created_metadata_ids)
        updated_metadata_ids = args_metadata.reject { |m| m[:id].nil? }.map { |m| m[:id] }
        not_needed_ids = customer.metadata.pluck(:id) - updated_metadata_ids - created_metadata_ids

        customer.metadata.where(id: not_needed_ids).destroy_all
      end
    end
  end
end
