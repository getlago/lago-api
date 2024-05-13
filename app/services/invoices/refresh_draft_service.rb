# frozen_string_literal: true

module Invoices
  class RefreshDraftService < BaseService
    def initialize(invoice:, context: :refresh)
      @invoice = invoice
      @subscription_ids = invoice.subscriptions.pluck(:id)
      @context = context

      # NOTE: Recurring status (meaning billed automatically from the recurring billing process)
      #       should be kept to prevent double billing on billing day
      @recurring = invoice.invoice_subscriptions.first&.recurring || false

      # NOTE: upgrading is used as a not persisted reasong as it means
      #       one subscription starting and a second one terminating
      @invoicing_reason = if @recurring
        :subscription_periodic
      else
        invoice.invoice_subscriptions.first&.invoicing_reason&.to_sym || :upgrading
      end

      super
    end

    def call
      result.invoice = invoice
      return result unless invoice.draft?

      ActiveRecord::Base.transaction do
        invoice.update!(ready_to_be_refreshed: false) if invoice.ready_to_be_refreshed?

        old_fee_values = invoice_credit_note_items.map do |item|
          {credit_note_item_id: item.id, fee_amount_cents: item.fee&.amount_cents}
        end
        cn_subscription_ids = invoice.credit_notes.map do |cn|
          {credit_note_id: cn.id, subscription_id: cn.fees.pick(:subscription_id)}
        end
        invoice.credit_notes.each { |cn| cn.items.update_all(fee_id: nil) } # rubocop:disable Rails/SkipsModelValidations

        timestamp = fetch_timestamp

        invoice.fees.destroy_all

        invoice.invoice_subscriptions.destroy_all
        invoice.applied_taxes.destroy_all

        Invoices::CreateInvoiceSubscriptionService.call(
          invoice:,
          subscriptions: Subscription.find(subscription_ids),
          timestamp:,
          invoicing_reason:,
          refresh: true,
        ).raise_if_error!

        calculate_result = Invoices::CalculateFeesService.call(
          invoice: invoice.reload,
          recurring:,
          context:,
        )

        invoice.credit_notes.each do |credit_note|
          subscription_id = cn_subscription_ids.find { |h| h[:credit_note_id] == credit_note.id }[:subscription_id]
          fee = invoice.fees.subscription.find_by(subscription_id:)
          CreditNotes::RefreshDraftService.call(credit_note:, fee:, old_fee_values:)
        end

        return calculate_result unless calculate_result.success?

        # NOTE: In case of a refresh the same day of the termination.
        invoice.fees.update_all(created_at: invoice.created_at) # rubocop:disable Rails/SkipsModelValidations
      end

      result
    end

    private

    attr_accessor :invoice, :subscription_ids, :invoicing_reason, :recurring, :context

    def fetch_timestamp
      fee = invoice.fees.first
      # NOTE: Adding 1 second because of to_i rounding.
      return invoice.created_at + 1.second unless fee&.properties&.[]('timestamp')

      DateTime.parse(fee.properties['timestamp'])
    end

    def invoice_credit_note_items
      CreditNoteItem
        .joins(:credit_note)
        .where(credit_note: {invoice_id: invoice.id})
    end
  end
end
