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

      super
    end

    def call
      result.invoice = invoice
      return result unless invoice.draft?

      ActiveRecord::Base.transaction do
        cn_subscription_ids = invoice.credit_notes.map do |cn|
          { credit_note_id: cn.id, subscription_id: cn.fees.pick(:subscription_id) }
        end
        invoice.credit_notes.each { |cn| cn.items.update_all(fee_id: nil) } # rubocop:disable Rails/SkipsModelValidations

        invoice.fees.destroy_all
        invoice.invoice_subscriptions.destroy_all
        invoice.update!(vat_rate: invoice.customer.applicable_vat_rate)

        calculate_result = Invoices::CalculateFeesService.call(
          invoice: invoice.reload,
          subscriptions: Subscription.find(subscription_ids),
          timestamp: invoice.created_at.to_i + 1.second, # NOTE: Adding 1 second because of to_i rounding.
          recurring:,
          context:,
        )

        invoice.credit_notes.each do |credit_note|
          subscription_id = cn_subscription_ids.find { |h| h[:credit_note_id] == credit_note.id }[:subscription_id]
          fee = invoice.fees.subscription.find_by(subscription_id:)
          credit_note.items.update_all(fee_id: fee.id) # rubocop:disable Rails/SkipsModelValidations
        end

        return calculate_result unless calculate_result.success?

        # NOTE: In case of a refresh the same day of the termination.
        invoice.fees.update_all(created_at: invoice.created_at) # rubocop:disable Rails/SkipsModelValidations
      end

      result
    end

    private

    attr_accessor :invoice, :subscription_ids, :recurring, :context
  end
end
