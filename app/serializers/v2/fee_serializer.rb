# frozen_string_literal: true

module V2
  # A fee billed from the product catalog: it names the contract, product and
  # rate card it was priced from, not the v1 subscription and charge.
  class FeeSerializer < ModelSerializer
    PRELOADS = [
      :applied_taxes,
      {pricing_unit_usage: :pricing_unit},
      :true_up_fee,
      :rate_card_rate,
      :product_filter,
      {invoice: :customer},
      {contract: :customer},
      {contract_rate_card: :rate_card},
      {invoiceable: :product_category}
    ].freeze

    def serialize
      {
        lago_id: model.id,
        lago_invoice_id: model.invoice_id,
        fee_type: model.fee_type,
        lago_customer_id: customer&.id,
        external_customer_id: customer&.external_id,
        lago_contract_id: model.contract_id,
        external_contract_id: model.contract&.external_id,
        lago_product_id: product&.id,
        product_code: product&.code,
        lago_product_category_id: product_category&.id,
        product_category_code: product_category&.code,
        lago_product_filter_id: model.product_filter_id,
        product_filter_code: model.product_filter&.code,
        lago_rate_card_id: rate_card&.id,
        rate_card_code: rate_card&.code,
        lago_rate_id: model.rate_card_rate_id,
        rate_code: model.rate_card_rate&.code,
        lago_rate_override_id: model.rate_override_id,
        lago_true_up_parent_fee_id: model.true_up_parent_fee_id,
        lago_true_up_fee_id: model.true_up_fee&.id,
        event_transaction_id: model.pay_in_advance_event_transaction_id,
        display_on_invoice: rate_card&.display_on_invoice,
        product_invoice_display_name: product&.invoice_name,
        product_category_invoice_display_name: product_category&.invoice_name,
        product_filter_invoice_display_name: model.product_filter&.invoice_name,
        filters:,
        billing_timing: model.pay_in_advance? ? "advance" : "arrears",
        grouped_by: model.grouped_by,
        from_datetime: datetime_property("from_datetime"),
        to_datetime: datetime_property("to_datetime"),
        currency: model.amount_currency,
        units: model.units,
        total_aggregated_units: model.total_aggregated_units,
        events_count: model.events_count,
        unit_amount_cents: model.unit_amount_cents,
        precise_unit_amount_cents: model.precise_unit_amount * model.amount.currency.subunit_to_unit,
        amount_cents: model.amount_cents,
        precise_amount_cents: model.precise_amount_cents,
        precise_coupons_amount_cents: model.precise_coupons_amount_cents,
        sub_total_excluding_taxes_amount_cents: model.sub_total_excluding_taxes_amount_cents.round,
        sub_total_excluding_taxes_precise_amount_cents: model.sub_total_excluding_taxes_precise_amount_cents,
        taxes_amount_cents: model.taxes_amount_cents,
        taxes_precise_amount_cents: model.taxes_precise_amount_cents,
        total_amount_cents: model.total_amount_cents,
        precise_total_amount_cents: model.precise_total_amount_cents,
        amount_details: ::RateProperties.present(model.amount_details),
        pricing_unit_details:,
        payment_status: model.payment_status,
        succeeded_at: model.succeeded_at&.iso8601,
        failed_at: model.failed_at&.iso8601,
        refunded_at: model.refunded_at&.iso8601,
        applied_taxes:,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end

    private

    # Fee#customer goes through the subscription, which a product fee has none of.
    def customer
      model.invoice&.customer || model.contract&.customer
    end

    def product
      return @product if defined?(@product)

      @product = record_or_discarded(model.invoiceable, Product, model.invoiceable_id)
    end

    def product_category
      return @product_category if defined?(@product_category)

      @product_category = product && record_or_discarded(product.product_category, ProductCategory, product.product_category_id)
    end

    def rate_card
      return @rate_card if defined?(@rate_card)

      applied = model.contract_rate_card
      @rate_card = applied && record_or_discarded(applied.rate_card, RateCard, applied.rate_card_id)
    end

    # The default scopes hide a discarded catalog record from its association;
    # a fee is a historical record and must still name what it billed.
    def record_or_discarded(record, klass, id)
      record || (id && klass.with_discarded.find_by(id:))
    end

    # Fees created before filter values were stored fall back to the filter's current values.
    def filters
      if model.properties.key?("product_filter_values")
        model.properties["product_filter_values"]
      else
        model.product_filter&.to_h
      end
    end

    def datetime_property(key)
      model.properties[key]&.to_time&.utc&.iso8601
    end

    def pricing_unit_details
      return if model.pricing_unit_usage.nil?

      ::V2::Fees::PricingUnitDetailsSerializer.new(model.pricing_unit_usage).serialize
    end

    def applied_taxes
      ::CollectionSerializer.new(
        model.applied_taxes,
        ::V2::Fees::AppliedTaxSerializer,
        collection_name: "applied_taxes"
      ).serialize[:applied_taxes]
    end
  end
end
