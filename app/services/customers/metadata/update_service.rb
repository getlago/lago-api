# frozen_string_literal: true

module Customers
  module Metadata
    class UpdateService < BaseService
      def initialize(customer:)
        @customer = customer
        super
      end

      def call(params:)
        created_metadata_ids = []

        hash_metadata = params.map { |m| m.to_h.deep_symbolize_keys }
        hash_metadata.each do |payload_metadata|
          metadata = customer.metadata.find_by(id: payload_metadata[:id])

          if metadata
            metadata.update!(payload_metadata)

            next
          end

          created_metadata = create_metadata(payload_metadata)
          created_metadata_ids.push(created_metadata.id)
        end

        # NOTE: Delete metadata that are no more linked to the customer
        sanitize_charges(hash_metadata, created_metadata_ids)

        result.customer = customer
        result
      end

      private

      attr_reader :customer

      def create_metadata(params)
        customer.metadata.create!(
          key: params[:key],
          value: params[:value],
          display_in_invoice: params[:display_in_invoice],
        )
      end

      def sanitize_charges(args_metadata, created_metadata_ids)
        updated_metadata_ids = args_metadata.reject { |m| m[:id].nil? }.map { |m| m[:id] }
        not_needed_ids = customer.metadata.pluck(:id) - updated_metadata_ids - created_metadata_ids

        customer.metadata.where(id: not_needed_ids).destroy_all
      end
    end
  end
end
