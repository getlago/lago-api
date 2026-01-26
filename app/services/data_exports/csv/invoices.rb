# frozen_string_literal: true

require "csv"
require "forwardable"

module DataExports
  module Csv
    class Invoices < BaseCsvService
      extend Forwardable

      def initialize(data_export_part:, serializer_klass: V1::InvoiceSerializer)
        @data_export_part = data_export_part
        @serializer_klass = serializer_klass
        @progressive_billing_enabled = organization&.progressive_billing_enabled?
        super
      end

      def self.base_headers
        %w[
          lago_id
          sequential_id
          partner_billing
          issuing_date
          customer_lago_id
          customer_external_id
          customer_name
          customer_email
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
          total_due_amount_cents
          total_paid_amount_cents
          total_offsetted_credit_note_amount_cents
        ]
      end

      def headers
        base = self.class.base_headers.dup
        base << "progressive_billing_credit_amount_cents" if progressive_billing_enabled
        base << "billing_entity_code" if org_has_multiple_billing_entities?
        base
      end

      private

      attr_reader :data_export_part, :serializer_klass, :progressive_billing_enabled

      def serialize_item(invoice, csv)
        serialized_invoice = serializer_klass
          .new(invoice, includes: %i[customer])
          .serialize

        row = [
          serialized_invoice[:lago_id],
          serialized_invoice[:sequential_id],
          serialized_invoice[:self_billed],
          serialized_invoice[:issuing_date],
          serialized_invoice.dig(:customer, :lago_id),
          serialized_invoice.dig(:customer, :external_id),
          serialized_invoice.dig(:customer, :name),
          serialized_invoice.dig(:customer, :email),
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
          serialized_invoice[:payment_overdue],
          serialized_invoice[:total_due_amount_cents],
          serialized_invoice[:total_paid_amount_cents],
          serialized_invoice[:total_offsetted_credit_note_amount_cents]
        ]

        row << serialized_invoice[:progressive_billing_credit_amount_cents] if progressive_billing_enabled
        row << serialized_invoice[:billing_entity_code] if org_has_multiple_billing_entities?
        csv << row
      end

      def collection
        invoices = Invoice.find(data_export_part.object_ids)
        preload_offset_amounts(invoices)

        invoices
      end

      def preload_offset_amounts(invoices)
        offset_amounts = CreditNote
          .where(invoice_id: data_export_part.object_ids)
          .finalized
          .group(:invoice_id)
          .sum(:offset_amount_cents)

        invoices.each do |invoice|
          cached_value = offset_amounts[invoice.id] || 0
          invoice.define_singleton_method(:offset_amount_cents) { cached_value }
        end
      end

      def organization
        @organization ||= data_export_part.data_export.organization
      end

      def org_has_multiple_billing_entities?
        return false unless organization

        organization.billing_entities.count > 1
      end
    end
  end
end
