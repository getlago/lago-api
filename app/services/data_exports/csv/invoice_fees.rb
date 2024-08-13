# frozen_string_literal: true

require 'csv'
require 'forwardable'

module DataExports
  module Csv
    class InvoiceFees < Invoices
      DEFAULT_BATCH_SIZE = 50

      extend Forwardable

      def initialize(
        data_export:,
        invoice_serializer_klass: V1::InvoiceSerializer,
        fee_serializer_klass: V1::FeeSerializer,
        subscription_serializer_klass: V1::SubscriptionSerializer,
        output: Tempfile.create
      )

        @data_export = data_export
        @invoice_serializer_klass = invoice_serializer_klass
        @fee_serializer_klass = fee_serializer_klass
        @subscription_serializer_klass = subscription_serializer_klass
        @output = output
        @batch_size = DEFAULT_BATCH_SIZE
      end

      def call
        ::CSV.open(output, 'wb', headers: true) do |csv|
          csv << headers

          invoices.find_each(batch_size:).lazy.each do |invoice|
            serialized_invoice = invoice_serializer_klass.new(invoice).serialize

            invoice
              .fees
              .includes(
                :invoice,
                :subscription,
                :charge,
                :true_up_fee,
                :customer,
                :billable_metric,
                {charge_filter: {values: :billable_metric_filter}}
              )
              .find_each(batch_size:)
              .lazy
              .each do |fee|
              serialized_fee = fee_serializer_klass.new(fee).serialize

              serialized_subscription = fee.subscription ? subscription_serializer_klass.new(fee.subscription).serialize : {}

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
                serialized_subscription[:external_id],
                serialized_subscription[:plan_code],
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

        output.rewind
      end

      private

      attr_reader :invoice_serializer_klass, :fee_serializer_klass, :subscription_serializer_klass

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
