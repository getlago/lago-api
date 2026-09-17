# frozen_string_literal: true

module QuoteVersions
  class UpdateService < BaseService
    include OrderForms::Premium
    include Currencies

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

      if quote_version.currency_changed? && amendment?
        return result.single_validation_failure!(field: :currency, error_code: "not_supported_for_order_type")
      end

      realign_billing_items_currency!

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

    # An amendment restates a subscription that is already invoicing in its plan's currency, and the
    # quote takes that currency at creation. Repricing it here would switch a running subscription
    # mid-life, leaving its invoice history in the currency it started in.
    def amendment?
      quote_version.quote.order_type == "subscription_amendment"
    end

    # The billing items carry their own copy of the currency, which the rendered quote reads, so the
    # stored payload is realigned rather than resolved later from the deal.
    #
    # This runs before the structural pass, on a payload that is whatever JSON the caller sent, so
    # anything the validator would reject is left exactly as it arrived for it to report -- shapes and
    # values alike. Correcting a stale currency is the job here; silently accepting a malformed one
    # would mean the caller gets a saved quote instead of the error the schema exists to raise.
    #
    # Every update realigns, not only the ones changing the currency: the payload is rewritten
    # wholesale by whoever saves it, so a copy the deal no longer matches can arrive at any time and
    # would otherwise sit there until it blocked approval. Realigning is idempotent, so an already
    # coherent payload is left untouched.
    def realign_billing_items_currency!
      # Nothing coherent to realign against: a blank currency is still editable at this scope, and an
      # invalid one is about to fail validation, so stamping either across the payload would only
      # spread a value the deal does not have.
      return if self.class.currency_list.exclude?(quote_version.currency)

      items = billing_items
      return if items.empty?

      realigned = items.dup
      realigned["plans"] = realigned_plans(items["plans"]) if items.key?("plans")
      realigned["coupons"] = realigned_coupons(items["coupons"]) if items.key?("coupons")
      realigned["walletCredits"] = realigned_wallet_credits(items["walletCredits"]) if items.key?("walletCredits")

      quote_version.billing_items = realigned
    end

    def realigned_plans(plans)
      return plans unless plans.is_a?(Array)

      plans.map do |item|
        next item unless item.is_a?(Hash)

        plan = catalog_plans_by_id[item["id"]]
        next item if plan.nil?

        with_currency_override(item, catalog_currency: plan.amount_currency)
      end
    end

    def realigned_coupons(coupons)
      return coupons unless coupons.is_a?(Array)

      coupons.map do |item|
        next item unless item.is_a?(Hash)

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
    # currency the deal no longer uses, and fails validation exactly as a missing one did.
    #
    # Emptying the overrides leaves an empty object rather than removing the key. Everything reading
    # the payload treats a missing key, an empty object and nil alike, so the shape is chosen for the
    # readers that render the quote: they reach for `overrides.name` and a key that disappeared takes
    # the whole page down with it.
    #
    # Only the currency key is ever touched, so a negotiated amount, a charge override or anything
    # else the deal states survives a currency change untouched. The figure is not converted.
    def with_currency_override(item, catalog_currency:)
      submitted = item["overrides"]
      # Null is a shape the schema accepts, so it realigns like an absent key. Anything else that is
      # not an object does not, and coercing it into one here would quietly answer the question the
      # structural pass is about to ask.
      return item unless submitted.nil? || submitted.is_a?(Hash)

      overrides = submitted || {}
      stated = overrides["amountCurrency"]
      # Same for the value it states: a currency that is not one is kept as submitted, rather than
      # replaced by a valid payload the caller never sent.
      return item unless stated.nil? || self.class.currency_list.include?(stated)

      realigned = if catalog_currency == quote_version.currency
        overrides.except("amountCurrency")
      else
        overrides.merge("amountCurrency" => quote_version.currency)
      end

      # An item that never carried the key, on a deal the catalog already matches, is left exactly as
      # it arrived rather than gaining an empty object.
      return item if realigned == overrides

      item.merge("overrides" => realigned)
    end

    def realigned_wallet_credits(wallet_credits)
      return wallet_credits unless wallet_credits.is_a?(Array)

      wallet_credits.map do |item|
        next item unless item.is_a?(Hash)

        payload = item["payload"]
        next item unless payload.is_a?(Hash)

        # Only a credit stating a real currency has anything stale to realign. One stating none keeps
        # stating none, because execution falls back to the deal's own, and one stating something that
        # is not a currency keeps that too, for the validator to report.
        next item unless self.class.currency_list.include?(payload["currency"])

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
      items = billing_items[key]
      return [] unless items.is_a?(Array)

      items.filter_map { it["id"] if it.is_a?(Hash) }
    end

    # The structural pass rejects a payload that is not an object, but it runs after this.
    def billing_items
      items = quote_version.billing_items
      items.is_a?(Hash) ? items.deep_stringify_keys : {}
    end
  end
end
