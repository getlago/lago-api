# frozen_string_literal: true

module QuoteVersions
  # A quote carries dates the execution flow re-validates and refuses in the past: the subscription
  # ending date, a wallet expiration and a recurring rule expiration. Whichever comes first bounds
  # the whole deal, so a signing window or an execution date landing after it produces a failed
  # order rather than a subscription. one_off quotes carry none of them.
  module DealExpiration
    def self.earliest(quote_version)
      items = billing_items(quote_version)

      [
        *plan_end_dates(items),
        *wallet_expirations(items)
      ].filter_map { Utils::Datetime.parse_iso8601(it)&.to_date }.min
    end

    # An unbounded deal, a blank value and a value no date can be read from all pass: only a date
    # the deal no longer covers is refused, the boundary day included, since the execution flow
    # requires the ending date to be strictly after the day it runs.
    def self.covers?(quote_version, value)
      expiration = earliest(quote_version)
      return true if expiration.nil?

      date = Utils::Datetime.parse_iso8601(value)&.to_date
      return true if date.nil?

      date < expiration
    end

    # The structural pass rejects a payload that is not an object, but nothing stops a caller from
    # reading a version that never went through it.
    def self.billing_items(quote_version)
      items = quote_version.billing_items
      items.is_a?(Hash) ? items : {}
    end

    def self.plan_end_dates(items)
      Array(items["plans"]).map { it.dig("payload", "endDate") }
    end

    # Several recurring rules are legitimate on a draft, only an approved version is capped at one.
    def self.wallet_expirations(items)
      Array(items["walletCredits"]).flat_map do |item|
        payload = item["payload"] || {}

        [payload["expirationAt"], *Array(payload["recurringTransactionRules"]).map { it["expirationAt"] }]
      end
    end

    private_class_method :billing_items, :plan_end_dates, :wallet_expirations
  end
end
