# frozen_string_literal: true

# Evaluates wallet alerts as soon as a balance moves (UsageMonitoring::DispatchWalletAlertsService).
# Evaluating inline keeps the partition's ordering: the topic is keyed by wallet, so the consumer
# never evaluates one wallet's alerts twice at once.
class WalletAlertsConsumer < ApplicationConsumer
  def consume
    payloads = messages.map(&:payload).compact
    return if payloads.empty?

    unless License.premium?
      report(:skipped, :not_premium, by: payloads.size)
      return
    end

    # Evaluation reads the wallet from the database, so a batch needs one pass per wallet however
    # many times its balance moved. A wallet is resolved by its organization too, so that a payload
    # naming another organization's wallet is skipped rather than evaluated.
    payloads_by_wallet = payloads.group_by { [it["organization_id"], it["wallet_id"]] }
    wallets = Wallet.where(id: payloads_by_wallet.keys.map(&:last)).index_by { [it.organization_id, it.id] }

    payloads_by_wallet.each do |key, wallet_payloads|
      wallet = wallets[key]

      if wallet.nil?
        report(:skipped, :wallet_not_found)
        next
      end

      evaluate(wallet, wallet_payloads)
    end
  end

  private

  def evaluate(wallet, wallet_payloads)
    UsageMonitoring::ProcessWalletAlertsService.call!(wallet:)

    report(:evaluated, :none)
    report_latency(wallet_payloads)
  rescue => e
    # Raising out of #consume pauses the partition and replays the batch, re-evaluating every wallet
    # already done. The job retries this one wallet instead.
    report(:failed, :evaluation_raised)
    Rails.logger.error("[alerts] wallet alerts evaluation raised wallet_id=#{wallet.id}: #{e.class} #{e.message}")
    Sentry.capture_exception(e, extra: {wallet_id: wallet.id})

    UsageMonitoring::ProcessWalletAlertsJob.perform_later(wallet)
  end

  def report(outcome, reason, by: 1)
    Yabeda.usage_monitoring.wallet_alerts_outcomes_total.increment(
      {outcome: outcome.to_s, reason: reason.to_s}, by:
    )
  end

  def report_latency(wallet_payloads)
    now = Time.current.to_f

    wallet_payloads.each do |payload|
      next if payload["dispatched_at_ms"].nil?

      latency = now - (payload["dispatched_at_ms"].to_i / 1000.0)
      Yabeda.usage_monitoring.wallet_alerts_latency.measure({}, latency)
    end
  end
end
