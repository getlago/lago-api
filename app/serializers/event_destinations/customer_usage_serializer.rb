# frozen_string_literal: true

module EventDestinations
  class CustomerUsageSerializer < ModelSerializer
    def serialize
      {
        from_datetime: iso8601(model.from_datetime),
        to_datetime: iso8601(model.to_datetime),
        issuing_date: iso8601(model.issuing_date),
        currency: model.currency,
        amount_cents: model.amount_cents,
        wallets: wallets_usage,
        charges_usage: charges_usage
      }
    end

    private

    def iso8601(value)
      value.respond_to?(:iso8601) ? value.iso8601 : value
    end

    def wallets
      options[:wallets] || []
    end

    # The ongoing usage each wallet absorbs, as the wallet refresh allocated it: wallet targets,
    # allowed fee types, thresholds and the cascade are all already applied. Customer scoped, so a
    # customer with several subscriptions sees the same totals on each of their records.
    def wallets_usage
      wallets.map do |wallet|
        {
          lago_id: wallet.id,
          credits: wallet.credits_ongoing_usage_balance.to_s,
          amount_cents: wallet.ongoing_usage_balance_cents,
          amount_currency: wallet.balance_currency
        }
      end
    end

    def wallet_amounts
      options[:wallet_amounts] || {}
    end

    # A plan carries a charge per feature, so a customer using a handful of them would otherwise
    # ship a long tail of zeroes on every record. Dropping them keeps headroom under the 1MB cap.
    # Fee#non_zero? is the trim daily usage already applies, so both payloads agree on what counts.
    #
    # One entry per charge and wallet, and the entries add up exactly to the charge totals. Each part
    # of a charge's usage is split in proportion to what each wallet absorbed for it: its usage of the
    # billable metric, with usage whose events targeted a wallet kept apart, since only that wallet
    # pays for it.
    def charges_usage
      usage_fees = model.fees.select(&:non_zero?)
      amounts_by_key = usage_fees.group_by { amount_key(it) }.transform_values { |fees| fees.sum(&:amount_cents) }

      ledgers = Hash.new { |hash, key| hash[key] = Hash.new(0) }

      usage_fees.group_by(&:charge_id).flat_map do |_charge_id, charge_fees|
        parts = Hash.new { |hash, wallet_id| hash[wallet_id] = {units: 0, events_count: 0, amount_cents: 0} }

        charge_fees.group_by { amount_key(it) }.each do |key, fees|
          weights = wallet_weights(key, amounts_by_key[key])
          units = split_units(fees.sum { BigDecimal(it.units) }, weights, ledgers[[key, :units]])
          events_count = split_integer(fees.sum { it.events_count.to_i }, weights, ledgers[[key, :events_count]])
          amount_cents = split_integer(fees.sum(&:amount_cents), weights, ledgers[[key, :amount_cents]])

          weights.each_key do |wallet_id|
            parts[wallet_id][:units] += units[wallet_id]
            parts[wallet_id][:events_count] += events_count[wallet_id]
            parts[wallet_id][:amount_cents] += amount_cents[wallet_id]
          end
        end

        fee = charge_fees.first

        parts.sort_by { |wallet_id, part| [wallet_id.nil? ? 1 : 0, -part[:amount_cents], wallet_id.to_s] }.map do |wallet_id, part|
          {
            units: part[:units].to_s,
            events_count: part[:events_count],
            amount_cents: part[:amount_cents],
            amount_currency: fee.amount_currency,
            charge: {
              lago_id: fee.charge_id,
              code: fee.charge.code
            },
            billable_metric: {
              lago_id: fee.charge.billable_metric_id,
              code: fee.charge.billable_metric.code
            },
            wallet_id:
          }
        end
      end
    end

    def amount_key(fee)
      WalletTransaction.billable_metric_amount_key(fee.charge.billable_metric_id, target_wallet_code(fee))
    end

    # Like the wallet allocations, which only keep targeted usage apart when the organization lets
    # events target wallets.
    def target_wallet_code(fee)
      if fee.charge.accepts_target_wallet && events_targeting_wallets_enabled?(fee)
        fee.grouped_by&.dig(::Charge::EVENT_TARGET_WALLET_CODE)
      end
    end

    def events_targeting_wallets_enabled?(fee)
      return @events_targeting_wallets_enabled if defined?(@events_targeting_wallets_enabled)

      @events_targeting_wallets_enabled = fee.organization.events_targeting_wallets_enabled?
    end

    # The money each wallet absorbed for this part of the usage, largest first. Wallets are recorded
    # per part, not per charge, so they are weighed against the part's amount across all the charges
    # of its billable metric. What no wallet absorbed goes to a nil wallet, and so does the whole
    # part when no wallet did.
    def wallet_weights(key, amount_cents)
      weights = wallet_amounts.fetch(key, {})
        .select { |_wallet_id, cents| cents.positive? }
        .sort_by { |wallet_id, cents| [-cents, wallet_id] }
        .to_h
      unattributed = amount_cents - weights.values.sum

      if unattributed.positive?
        weights.merge(nil => unattributed)
      elsif weights.empty?
        {nil => 1}
      else
        weights
      end
    end

    # Largest remainder, so the parts add up to the total. The ledger carries, per wallet, how much it
    # has been shorted so far on the billable metric: when a metric has several charges, the leftover
    # units go to whoever is owed most, so rounding does not keep favouring the same wallet.
    def split_integer(total, weights, ledger, factor = 1)
      sum = weights.values.sum
      exact = weights.transform_values { |weight| Rational(total * weight, sum) }
      parts = exact.transform_values(&:floor)
      owed = exact.to_h { |wallet_id, share| [wallet_id, ledger[wallet_id] + Rational(share - parts[wallet_id], factor)] }
      recipients = weights.keys.each_with_index.sort_by { |wallet_id, index| [-owed[wallet_id], index] }
        .first(total - parts.values.sum).map(&:first)

      recipients.each { parts[it] += 1 }
      parts.each_key { |wallet_id| ledger[wallet_id] = owed[wallet_id] - (recipients.include?(wallet_id) ? Rational(1, factor) : 0) }
      parts
    end

    # Split like the integers, at the precision of the total, so no part can go negative.
    def split_units(units, weights, ledger)
      factor = 10**units.scale

      split_integer((units * factor).to_i, weights, ledger, factor).transform_values { BigDecimal(it) / factor }
    end
  end
end
