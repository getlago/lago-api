# frozen_string_literal: true

module V2
  class RateCardSerializer < ModelSerializer
    # The latest effective rate, as RateCard#active_rate selects it.
    expandable(:active_rate, serializer: ::V2::RateCardRateSerializer) { active_rate }
    # As /taxes lists them.
    expandable(:taxes, serializer: ::V2::TaxSerializer) { model.applied_taxes.listed.filter_map(&:tax) }
    # As /rates lists them, sorted in memory so that each status reads its siblings from the
    # loaded rates rather than querying them.
    expandable(:rates, serializer: ::V2::RateCardRateSerializer) { model.rates.sort_by(&:effective_from).reverse }
    expandable :product, serializer: ::V2::ProductSerializer
    # With the keys of its values, rather than one billable metric filter query per value.
    expandable(:product_filter, serializer: ::V2::ProductFilterSerializer) do
      model.product_filter&.tap { ActiveRecord::Associations::Preloader.new(records: [it], associations: {values: :billable_metric_filter}).call }
    end

    def serialize
      {
        lago_id: model.id,
        product_code: model.product.code,
        product_filter_code: model.product_filter&.code,
        name: model.name,
        code: model.code,
        description: model.description,
        currency: model.currency,
        billing_timing: model.billing_timing,
        proration: model.proration,
        display_on_invoice: model.display_on_invoice,
        regroup_paid_fees: model.regroup_paid_fees,
        applied_pricing_unit_code: model.applied_pricing_unit_code,
        rates_count: model.rates.size,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        deleted_at: model.deleted_at&.iso8601
      }
    end

    private

    # From the rates when they are expanded too, so that both expansions read the same rows.
    def active_rate
      return model.active_rate unless include?(:rates)

      now = Time.current
      model.rates.select { it.effective_from <= now }.max_by(&:effective_from)
    end
  end
end
