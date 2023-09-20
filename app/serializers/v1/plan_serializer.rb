# frozen_string_literal: true

module V1
  class PlanSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        name: model.name,
        invoice_display_name: model.invoice_display_name,
        created_at: model.created_at.iso8601,
        code: model.code,
        interval: model.interval,
        description: model.description,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        trial_period: model.trial_period,
        pay_in_advance: model.pay_in_advance,
        bill_charges_monthly: model.bill_charges_monthly,
        active_subscriptions_count:,
        draft_invoices_count:,
        parent_id: model.parent_id,
      }

      payload.merge!(charges) if include?(:charges)
      payload.merge!(taxes) if include?(:taxes)

      payload
    end

    private

    def charges
      ::CollectionSerializer.new(
        model.charges,
        ::V1::ChargeSerializer,
        collection_name: 'charges',
        includes: include?(:taxes) ? %i[taxes] : [],
      ).serialize
    end

    def active_subscriptions_count
      model.subscriptions.active.count
    end

    def draft_invoices_count
      model.subscriptions
        .joins(:invoices)
        .merge(Invoice.draft)
        .select(:invoice_id)
        .distinct
        .count
    end

    def taxes
      ::CollectionSerializer.new(
        model.taxes,
        ::V1::TaxSerializer,
        collection_name: 'taxes',
      ).serialize
    end
  end
end
