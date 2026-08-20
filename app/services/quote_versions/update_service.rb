# frozen_string_literal: true

module QuoteVersions
  class UpdateService < BaseService
    include OrderForms::Premium

    attr_reader :quote_version, :params

    Result = BaseResult[:quote_version]

    # The middleware is used rather than an inline produce because the diff is what makes this
    # entry useful, and object_changes is only computed when produce wraps the call.
    activity_loggable(action: "quote.updated", record: -> { quote_version })

    def initialize(quote_version:, params:)
      @quote_version = quote_version
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: "quote_version") unless quote_version
      return result.forbidden_failure! unless order_forms_enabled?(quote_version.organization)
      return result.single_validation_failure!(field: :status, error_code: "not_editable") unless editable?

      quote_version.assign_attributes(params.slice(:billing_items, :content, :currency, :billing_entity_id))

      if quote_version.currency_changed?
        return result if refuse_currency_change!
        realign_billing_items_currency!
      end

      validator = QuoteVersions::Validators.for(result, quote_version:, scope: :update)
      return result if validator && !validator.valid?

      quote_version.save!
      result.quote_version = quote_version
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    def editable?
      quote_version.draft?
    end

    # Returns truthy once a failure is recorded, so the caller stops before rewriting anything.
    def refuse_currency_change!
      return unless amendment?

      result.single_validation_failure!(field: :currency, error_code: "not_supported_for_order_type")
    end

    # An amendment restates a subscription that is already invoicing in its plan's currency, and the
    # quote takes that currency at creation. Repricing it here would switch a running subscription
    # mid-life, leaving its invoice history in the currency it started in.
    def amendment?
      quote_version.quote.order_type == "subscription_amendment"
    end

    # The billing items carry their own copy of the currency, which the rendered quote reads, so the
    # stored payload is realigned rather than resolved later from the deal.
    def realign_billing_items_currency!
      items = billing_items
      return if items.empty?

      realigned = items.dup
      realigned["plans"] = realigned_plans(items["plans"]) if items.key?("plans")
      realigned["coupons"] = realigned_coupons(items["coupons"]) if items.key?("coupons")
      realigned["walletCredits"] = realigned_wallet_credits(items["walletCredits"]) if items.key?("walletCredits")

      quote_version.billing_items = realigned
    end

    def realigned_plans(plans)
      Array(plans).map do |item|
        plan = catalog_plans_by_id[item["id"]]
        next item if plan.nil?

        with_currency_override(item, catalog_currency: plan.amount_currency)
      end
    end

    def realigned_coupons(coupons)
      Array(coupons).map do |item|
        coupon = catalog_coupons_by_id[item["id"]]
        next item if coupon.nil?

        # A percentage coupon is never priced in a currency, so it reads as already matching and any
        # override it carries is stale.
        catalog_currency = coupon.fixed_amount? ? coupon.amount_currency : quote_version.currency

        with_currency_override(item, catalog_currency:)
      end
    end

    # The override states the deal currency only while the catalog record is priced in another one.
    # Dropping it once the two agree matters as much as setting it: an override left behind states a
    # currency the deal no longer uses, and fails validation exactly as a missing one did. The key
    # goes away with it so the item stops carrying an overrides object it no longer needs, which is
    # what keeps the execution service from minting a duplicate override plan.
    def with_currency_override(item, catalog_currency:)
      overrides = item["overrides"] || {}
      realigned = if catalog_currency == quote_version.currency
        overrides.except("amountCurrency")
      else
        overrides.merge("amountCurrency" => quote_version.currency)
      end

      return item if realigned == overrides
      return item.except("overrides") if realigned.empty?

      item.merge("overrides" => realigned)
    end

    # A credit that stated no currency keeps stating none: the execution service falls back to the
    # deal's own, so there is nothing stale to realign.
    def realigned_wallet_credits(wallet_credits)
      Array(wallet_credits).map do |item|
        payload = item["payload"]
        next item unless payload.is_a?(Hash) && payload["currency"].present?

        item.merge("payload" => payload.merge("currency" => quote_version.currency))
      end
    end

    def catalog_plans_by_id
      @catalog_plans_by_id ||= quote_version
        .organization
        .plans
        .with_discarded
        .where(id: billing_item_ids("plans"))
        .index_by(&:id)
    end

    def catalog_coupons_by_id
      @catalog_coupons_by_id ||= quote_version
        .organization
        .coupons
        .with_discarded
        .where(id: billing_item_ids("coupons"))
        .index_by(&:id)
    end

    def billing_item_ids(key)
      Array(billing_items[key]).filter_map { it["id"] }
    end

    # The structural pass rejects a payload that is not an object, but it runs after this.
    def billing_items
      items = quote_version.billing_items
      items.is_a?(Hash) ? items.deep_stringify_keys : {}
    end
  end
end
