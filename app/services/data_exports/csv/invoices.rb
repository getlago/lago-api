# frozen_string_literal: true

require 'csv'
require 'forwardable'

module DataExports
  module Csv
    class Invoices < BaseService
      extend Forwardable

      def initialize(data_export_part:, serializer_klass: V1::InvoiceSerializer)
        @data_export_part = data_export_part
        @serializer_klass = serializer_klass
        super
      end

      def call
        result.csv_lines = ::CSV.generate(headers: false) do |csv|
          invoices.each do |invoice|
            csv << serialized_invoice(invoice)
          end
        end
        result
      end

      def self.headers
        %w[
          lago_id
          sequential_id
          issuing_date
          customer_lago_id
          customer_external_id
          customer_name
          customer_country
          customer_tax_identification_number
          invoice_number
          invoice_type
          payment_status
          status
          file_url
          currency
          fees_amount_cents
          coupons_amount_cents
          taxes_amount_cents
          credit_notes_amount_cents
          prepaid_credit_amount_cents
          total_amount_cents
          payment_due_date
          payment_dispute_lost_at
          payment_overdue
        ]
      end

      private

      attr_reader :data_export_part, :serializer_klass, :output, :batch_size

      def serialized_invoice(invoice)
        serialized_invoice = serializer_klass
          .new(invoice, includes: %i[customer])
          .serialize

        [
          serialized_invoice[:lago_id],
          serialized_invoice[:sequential_id],
          serialized_invoice[:issuing_date],
          serialized_invoice.dig(:customer, :lago_id),
          serialized_invoice.dig(:customer, :external_id),
          serialized_invoice.dig(:customer, :name),
          serialized_invoice.dig(:customer, :country),
          serialized_invoice.dig(:customer, :tax_identification_number),
          serialized_invoice[:number],
          serialized_invoice[:invoice_type],
          serialized_invoice[:payment_status],
          serialized_invoice[:status],
          serialized_invoice[:file_url],
          serialized_invoice[:currency],
          serialized_invoice[:fees_amount_cents],
          serialized_invoice[:coupons_amount_cents],
          serialized_invoice[:taxes_amount_cents],
          serialized_invoice[:credit_notes_amount_cents],
          serialized_invoice[:prepaid_credit_amount_cents],
          serialized_invoice[:total_amount_cents],
          serialized_invoice[:payment_due_date],
          serialized_invoice[:payment_dispute_lost_at],
          serialized_invoice[:payment_overdue]
        ]
      end

      def invoices
        Invoice.find(data_export_part.object_ids)
      end
    end
  end
end
