# frozen_string_literal: true

module V2
  class RateCardSerializer < ModelSerializer
    expandable :active_rate, serializer: ::V2::RateCardRateSerializer
    expandable :taxes, serializer: ::V2::TaxSerializer
    expandable :rates, serializer: ::V2::RateCardRateSerializer
    expandable :product, serializer: ::V2::ProductSerializer
    expandable :product_filter, serializer: ::V2::ProductFilterSerializer

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
        created_at: format_time(model.created_at),
        updated_at: format_time(model.updated_at),
        deleted_at: format_time(model.deleted_at)
      }
    end

    private

    # The latest effective rate, as RateCard#active_rate selects it. From the rates when they are
    # expanded too, so that both expansions read the same rows.
    def active_rate
      return model.active_rate unless include?(:rates)

      now = Time.current
      model.rates.select { it.effective_from <= now }.max_by(&:effective_from)
    end

    # The kept taxes, latest linked first.
    def taxes = model.applied_taxes.listed.preload(:tax).filter_map(&:tax)

    # As /rates lists them, sorted in memory so that each status reads its siblings from the
    # loaded rates rather than querying them.
    def rates = model.rates.sort_by(&:effective_from).reverse

    # With the keys of its values, rather than one billable metric filter query per value.
    def product_filter
      model.product_filter&.tap { ActiveRecord::Associations::Preloader.new(records: [it], associations: {values: :billable_metric_filter}).call }
    end
  end
end
