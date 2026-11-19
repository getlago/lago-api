# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module Invoices
        # Reuses the rates of earlier draft tax answers to price a request without the provider.
        #
        # Meant for estimates only, such as the ongoing balance of a wallet: every refresh changes
        # the amounts, so an exact answer (DraftTaxesCacheService) is never reused, while the rates
        # behind it rarely move. Each line is cached on its own, keyed on everything sent to the
        # provider except the amounts, the dates and the line identifiers. Any change of customer
        # address, tax identification number, currency, product mapping or integration settings is
        # a new key.
        #
        # Taxes can depend on the amount (a few US states cap or exempt items above or below a
        # price), so the amount band is part of the key: a line asks the provider again each time
        # it moves to another band.
        #
        # Rates also change on the provider side without Lago knowing (new registration, local rate
        # update), which the TTL bounds. The TTL is randomized so that customers refreshed during
        # the same burst do not all expire, and call the provider, at the same time.
        class DraftTaxRatesCache
          # IMPORTANT: bump when the key or the stored value changes, so old entries are ignored.
          CACHE_KEY_VERSION = "1"
          TTL = 24.hours
          TTL_JITTER = 12.hours

          BAND_WIDTH = 500
          WIDE_BAND_FROM = 5_000
          WIDE_BAND_WIDTH = 1_000

          TRANSACTION_DATES = %w[issuing_date tax_date].freeze
          LINE_VARIABLES = %w[item_key item_id amount_cents amount unit].freeze

          def initialize(integration:, payload:)
            @integration = integration
            @payload = payload
          end

          # Returns a provider-like answer built from the cached rates, or nil when one line has no
          # rate, in which case the provider must answer the whole request.
          def fetch
            return if keys.empty?

            cached = Rails.cache.read_multi(*keys)
            lines = keys.map { |key| cached[key] }

            if lines.all?
              track(:hit)
              build_body(lines)
            else
              track(:miss)
              nil
            end
          end

          def store(body)
            answered = body.is_a?(Hash) ? body.dig("succeededInvoices", 0, "fees") : nil
            return if answered.blank? || keys.empty?

            entries = request_lines.zip(keys).each_with_object({}) do |(line, key), memo|
              rates = (answer = answered_line(answered, line)) && line_rates(answer)
              memo[key] = rates if rates
            end
            return if entries.empty?

            Rails.cache.write_multi(entries, expires_in: TTL + rand(TTL_JITTER.to_i).seconds)
          end

          private

          attr_reader :integration, :payload

          def transaction
            payload.first
          end

          def request_lines
            Array(transaction&.dig("fees"))
          end

          def keys
            @keys ||= if transaction && request_lines.all? { |line| line_amount(line)&.positive? }
              request_lines.map { |line| line_key(line) }
            else
              []
            end
          end

          def line_key(line)
            [
              "draft-tax-rates",
              CACHE_KEY_VERSION,
              integration.id,
              integration.updated_at.utc.iso8601(6),
              transaction_digest,
              Digest::SHA256.hexdigest(line.except(*LINE_VARIABLES).to_json),
              band(line_amount(line))
            ].join("/")
          end

          def transaction_digest
            @transaction_digest ||= Digest::SHA256.hexdigest(transaction.except("fees", *TRANSACTION_DATES).to_json)
          end

          # Lines carry their amount in cents (Anrok) or in currency units (Avalara).
          def line_amount(line)
            if line.key?("amount_cents")
              cents = line["amount_cents"]
              cents && BigDecimal(cents.to_s) / subunit_to_unit
            elsif line["amount"].present?
              BigDecimal(line["amount"].to_s)
            end
          end

          def subunit_to_unit
            @subunit_to_unit ||= Money::Currency.new(transaction["currency"]).subunit_to_unit
          end

          # 0-499 is band 0, 500-999 band 1 and so on up to 5,000, then one band per 1,000.
          def band(amount)
            if amount < WIDE_BAND_FROM
              (amount / BAND_WIDTH).floor
            else
              (WIDE_BAND_FROM / BAND_WIDTH) + ((amount - WIDE_BAND_FROM) / WIDE_BAND_WIDTH).floor
            end
          end

          # Matched on identifiers rather than position, as the base service does, so that a
          # provider listing lines in another order cannot cache one product's rate for another.
          def answered_line(answered, line)
            answered.find { |answer| answer["item_key"].present? && answer["item_key"] == line["item_key"] } ||
              answered.find { |answer| answer["item_id"].present? && answer["item_id"].to_s == line["item_id"].to_s }
          end

          # Stores each tax as a share of the line amount, so it applies to any amount of the band.
          # The shares come from the unrounded breakdown amounts: the line tax is rounded to the
          # cent, so a small line (the start of a period) would store a skewed or zero rate.
          def line_rates(line)
            amount_cents = line["amount_cents"].to_d
            return unless amount_cents.positive? && line["tax_amount_cents"]

            breakdown = Array(line["tax_breakdown"])
            precise_tax = breakdown.sum { it["tax_amount"].to_d }
            line_tax = precise_tax.positive? ? precise_tax : line["tax_amount_cents"].to_d

            {
              # Taxes booked at zero while the provider computed at least one cent: the seller pays
              # them, and the line must keep showing no tax (see Taxes::BaseService#tax_breakdown).
              "seller_pays" => line["tax_amount_cents"].to_d.zero? && breakdown.any? { it["tax_amount"].to_d >= 1 },
              "tax_ratio" => (line_tax / amount_cents).to_s,
              "tax_breakdown" => breakdown.map do |item|
                if item["tax_amount"]
                  item.except("tax_amount").merge("tax_ratio" => (item["tax_amount"].to_d / amount_cents).to_s)
                else
                  item
                end
              end
            }
          end

          def build_body(rates)
            fees = request_lines.zip(rates).map do |line, line_rates|
              amount_cents = request_amount_cents(line)

              {
                "item_key" => line["item_key"],
                "item_id" => line["item_id"],
                "item_code" => line["item_code"],
                "amount_cents" => amount_cents.to_i,
                "tax_amount_cents" => line_rates["seller_pays"] ? 0 : (amount_cents * line_rates["tax_ratio"].to_d).round.to_i,
                # Breakdown amounts stay unrounded, as the provider sends them: they become the
                # precise taxes of the fee.
                "tax_breakdown" => line_rates["tax_breakdown"].map do |item|
                  ratio = item["tax_ratio"]
                  item = item.except("tax_ratio")
                  ratio ? item.merge("tax_amount" => (amount_cents * ratio.to_d).round(6).to_f) : item
                end
              }
            end

            {"succeededInvoices" => [{"fees" => fees}], "failedInvoices" => []}
          end

          def request_amount_cents(line)
            line_amount(line) * subunit_to_unit
          end

          def track(outcome)
            Yabeda.tax_providers.draft_tax_rates_cache_total.increment({provider: integration.provider_key, outcome:})
          end
        end
      end
    end
  end
end
