# frozen_string_literal: true

module QuoteVersions
  class ComputeMentionVariablesService < BaseService
    Result = BaseResult[:mention_variables]

    def initialize(quote_version:)
      @quote_version = quote_version
      super
    end

    def call
      result.mention_variables = {
        "customer_name" => customer.display_name,
        "customer_email" => customer.email,
        "organization_name" => organization.name,
        "organization_logo" => organization.logo_url,
        "billing_entity_name" => billing_entity&.name,
        "billing_entity_legal_name" => billing_entity&.legal_name,
        "billing_entity_address" => billing_entity_address,
        "billing_entity_tax_id" => billing_entity&.tax_identification_number,
        "billing_entity_email" => billing_entity&.email,
        "quote_number" => quote.number,
        "quote_date" => quote_date,
        "quote_version" => quote_version.version.to_s,
        "quote_currency" => quote_version.currency,
        "commercial_terms_term_duration" => term_duration,
        "commercial_terms_start_date" => term_start_date&.iso8601,
        "commercial_terms_payment_terms" => customer.applicable_net_payment_term
      }

      result
    end

    private

    attr_reader :quote_version

    delegate :quote, to: :quote_version
    delegate :customer, :organization, to: :quote
    # The version names the entity issuing the deal, falling back to the customer's own.
    delegate :billing_entity, to: :quote_version

    # Structured, locale-independent address parts. Formatting happens at read time in
    # QuoteVersions::MentionVariablesLocalizer.
    def billing_entity_address
      return if billing_entity.nil?

      {
        "address_line1" => billing_entity.address_line1,
        "address_line2" => billing_entity.address_line2,
        "locality" => billing_entity.city,
        "postal_code" => billing_entity.zipcode,
        "administrative_area" => billing_entity.state,
        "country_code" => billing_entity.country
      }
    end

    # The calendar date is frozen as a fact: the datetime is resolved in the customer
    # timezone, then stored as an ISO date string. Locale formatting is applied at read time.
    def quote_date
      quote.created_at.in_time_zone(customer.applicable_timezone).to_date.iso8601
    end

    # Picks the largest whole unit between the two dates (years, then months, then days)
    # and returns a raw { "unit", "count" } pair. A 12-month span becomes 1 year.
    def term_duration
      start_date = term_start_date
      end_date = term_end_date
      return if start_date.blank? || end_date.blank?

      months = whole_months_between(start_date, end_date)

      if months < 1
        {"unit" => "days", "count" => (end_date - start_date).to_i}
      elsif (months % 12).zero?
        {"unit" => "years", "count" => months / 12}
      else
        {"unit" => "months", "count" => months}
      end
    end

    # The deal term is not a quote-level field: every billing item carries its own dates, so the
    # commercial term is the span the quoted items cover. Plans state it as startDate/endDate, and
    # one_off add-ons as the service period their fee is billed for.
    #
    # An amendment restates a subscription that is already running and its plan need not carry a
    # start date, since the replacement inherits the target's anniversary date. That date is then
    # the term the customer signs.
    def term_start_date
      if one_off?
        add_on_dates("fromDatetime").min
      else
        plan_dates("startDate").min || amended_subscription_date
      end
    end

    def amended_subscription_date
      return unless quote.order_type == "subscription_amendment"

      quote.subscription&.subscription_at&.in_time_zone(customer.applicable_timezone)&.to_date
    end

    def term_end_date
      if one_off?
        add_on_dates("toDatetime").max
      else
        plan_dates("endDate").max
      end
    end

    def one_off?
      quote.order_type == "one_off"
    end

    # Same parsing as Orders::SubscriptionCreation::ExecuteService, the service these dates feed:
    # a bare calendar date and a full datetime are both accepted.
    def plan_dates(key)
      Array(billing_items["plans"]).filter_map do
        Utils::Datetime.parse_iso8601(it.dig("payload", key))&.to_date
      end
    end

    # Overrides win over the payload, the resolution Orders::OneOff::ExecuteService applies to the
    # dates it bills, and the one OneOff::BusinessValidator checks section by section.
    def add_on_dates(key)
      Array(billing_items["addOns"]).filter_map do |item|
        Utils::Datetime.parse_iso8601(item.dig("overrides", key) || item.dig("payload", key))&.to_date
      end
    end

    # The structural pass rejects a payload that is not an object, but a version can be read
    # before it ever went through one.
    def billing_items
      items = quote_version.billing_items
      items.is_a?(Hash) ? items : {}
    end

    # Whole calendar months between two dates, rounding down a partial trailing month.
    def whole_months_between(from, to)
      months = (to.year * 12 + to.month) - (from.year * 12 + from.month)
      (to.day < from.day) ? months - 1 : months
    end
  end
end
