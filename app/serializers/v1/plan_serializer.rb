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
        customers_count: model.customers_count,
        active_subscriptions_count: model.active_subscriptions_count,
        draft_invoices_count: model.draft_invoices_count,
        parent_id: model.parent_id
      }

      payload.merge!(charges) if include?(:charges)
      payload.merge!(usage_thresholds) if include?(:usage_thresholds)
      payload.merge!(taxes) if include?(:taxes)
      payload.merge!(minimum_commitment) if include?(:minimum_commitment) && model.minimum_commitment

      payload
    end

    private

    def charges
      ::CollectionSerializer.new(
        model.charges,
        ::V1::ChargeSerializer,
        collection_name: 'charges',
        includes: include?(:taxes) ? %i[taxes] : []
      ).serialize
    end

    def usage_thresholds
      ::CollectionSerializer.new(
        model.usage_thresholds,
        ::V1::UsageThresholdSerializer,
        collection_name: 'usage_thresholds'
      ).serialize
    end

    def minimum_commitment
      {
        minimum_commitment: V1::CommitmentSerializer.new(
          model.minimum_commitment,
          includes: include?(:taxes) ? %i[taxes] : []
        ).serialize.except(:commitment_type)
      }
    end

    def taxes
      ::CollectionSerializer.new(
        model.taxes,
        ::V1::TaxSerializer,
        collection_name: 'taxes'
      ).serialize
    end
  end
end
