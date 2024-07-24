# frozen_string_literal: true

require 'csv'
require 'forwardable'

module DataExports
  module Csv
    class Invoices < BaseService
      extend Forwardable

      def initialize(data_export:, serializer_klass: V1::InvoiceSerializer)
        @data_export = data_export
        @serializer_klass = serializer_klass
      end

      def call
        ::CSV.generate(headers: true) do |csv|
          csv << headers

          query.invoices.find_each do |invoice|
            serialized_invoice = serializer_klass
              .new(invoice, includes: %i[customer])
              .serialize

            csv << [
              serialized_invoice[:lago_id],
              serialized_invoice[:sequential_id],
              serialized_invoice[:issuing_date],
              serialized_invoice[:customer][:lago_id],
              serialized_invoice[:customer][:external_id],
              serialized_invoice[:customer][:country],
              serialized_invoice[:customer][:tax_identification_number],
              serialized_invoice[:number],
              serialized_invoice[:total_amount_cents],
              serialized_invoice[:currency],
              serialized_invoice[:invoice_type],
              serialized_invoice[:payment_status],
              serialized_invoice[:status],
              serialized_invoice[:file_url],
              serialized_invoice[:taxes_amount_cents],
              serialized_invoice[:credit_notes_amount_cents],
              serialized_invoice[:prepaid_credit_amount_cents],
              serialized_invoice[:coupons_amount_cents],
              serialized_invoice[:payment_due_date],
              serialized_invoice[:payment_dispute_lost_at],
              serialized_invoice[:payment_overdue]
            ]
          end
        end
      end

      private

      attr_reader :data_export, :serializer_klass

      def_delegators :data_export, :organization, :resource_query

      def headers
        %w[
          lago_id
          sequential_id
          issuing_date
          customer_lago_id
          customer_external_id
          customer_country
          customer_tax_identification_number
          invoince_number
          total_amount_cents
          currency
          invoice_type
          payment_status
          status
          file_url
          taxes_amount_cents
          credit_notes_amount_cents
          prepaid_credit_amount_cents
          coupons_amount_cents
          payment_due_date
          payment_dispute_lost_at
          payment_overdue
        ]
      end

      def query
        filters = resource_query.except(
          'search_term',
          'customer_id',
          'payment_dispute_lost',
          'payment_overdue',
          'payment_status',
          'status'
        )

        InvoicesQuery.new(organization: organization, pagination: nil).call(
          search_term: resource_query['search_term'],
          filters:,
          customer_id: resource_query['customer_id'],
          payment_dispute_lost: resource_query['payment_dispute_lost'],
          payment_overdue: resource_query['payment_overdue'],
          payment_status: resource_query['payment_status'],
          status: resource_query['status']
        )
      end
    end
  end
end
