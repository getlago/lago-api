# frozen_string_literal: true

require 'csv'
require 'forwardable'

module DataExports
  module Csv
    class InvoiceFees < Invoices
      extend Forwardable

      def call
        ::CSV.open(output, 'wb', headers: true) do |csv|
          csv << headers

          invoices.find_each do |invoice|
            serialized_invoice = serializer_klass
              .new(invoice, includes: %i[fees subscriptions])
              .serialize

            subscriptions = serialized_invoice[:subscriptions].index_by do |sub|
              sub[:lago_id]
            end

            serialized_invoice[:fees].each do |serialized_fee|
              subscription_id = serialized_fee[:lago_subscription_id]
              serialized_subscription = subscriptions[subscription_id]

              csv << [
                serialized_invoice[:lago_id],
                serialized_invoice[:number],
                serialized_invoice[:issuing_date],
                serialized_fee[:lago_id],
                serialized_fee.dig(:item, :type),
                serialized_fee.dig(:item, :code),
                serialized_fee.dig(:item, :name),
                serialized_fee.dig(:item, :description),
                serialized_fee.dig(:item, :invoice_display_name),
                serialized_fee.dig(:item, :filter_invoice_display_name),
                serialized_fee.dig(:item, :grouped_by),
                serialized_subscription&.dig(:external_id),
                serialized_subscription&.dig(:plan_code),
                serialized_fee[:from_date],
                serialized_fee[:to_date],
                serialized_fee[:total_amount_currency],
                serialized_fee[:units],
                serialized_fee[:precise_unit_amount],
                serialized_fee[:taxes_amount_cents],
                serialized_fee[:total_amount_cents]
              ]
            end
          end
        end
      end

      private

      def headers
        %w[
          invoice_lago_id
          invoice_number
          invoice_issuing_date
          fee_lago_id
          fee_item_type
          fee_item_code
          fee_item_name
          fee_item_description
          fee_item_invoice_display_name
          fee_item_filter_invoice_display_name
          fee_item_grouped_by
          subscription_external_id
          subscription_plan_code
          fee_from_date_utc
          fee_to_date_utc
          fee_amount_currency
          fee_units
          fee_precise_unit_amount
          fee_taxes_amount_cents
          fee_total_amount_cents
        ]
      end
    end
  end
end
