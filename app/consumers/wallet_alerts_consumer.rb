# frozen_string_literal: true

# The topic is keyed by wallet, so a wallet's messages are evaluated in order. ProcessWalletAlertsJob
# can still evaluate the same wallet: ProcessAlertService reads the wallet under the alert lock.
class WalletAlertsConsumer < ApplicationConsumer
  # A batch outliving max.poll.interval.ms gets the member evicted and the batch replayed by its
  # next owner. What the deadline cuts goes to the job.
  CONSUME_DEADLINE = 2.minutes

  # There is no dead letter topic: past this, the batch's wallets go to the job and the batch is
  # skipped. Until the job has them, the batch keeps retrying.
  MAX_ATTEMPTS = 3

  def consume
    payloads = messages.filter_map { parse(it) }
    return if payloads.empty?

    unless License.premium?
      report(:skipped, :not_premium, by: payloads.size)
      return
    end

    # One evaluation per wallet however many times its balance moved in the batch.
    payloads_by_wallet = payloads.group_by { [it["organization_id"], it["wallet_id"]] }
    wallets = resolve(payloads_by_wallet.keys)
    deadline = Time.current + CONSUME_DEADLINE

    payloads_by_wallet.each do |key, wallet_payloads|
      wallet = wallets[key]

      if wallet.nil?
        report(:skipped, :wallet_not_found)
      elsif Time.current > deadline
        report(:deferred, :deadline)
        UsageMonitoring::ProcessWalletAlertsJob.perform_later(wallet)
      else
        evaluate(wallet, wallet_payloads)
      end
    end
  rescue => e
    raise if attempt < MAX_ATTEMPTS || payloads_by_wallet.nil?

    # Evaluation is idempotent under the alert lock, so wallets already evaluated can go again.
    # Raising here (Redis or the database still down) keeps the batch for the next attempt.
    hand_to_job(resolve(payloads_by_wallet.keys).values)

    Rails.logger.error("[alerts] wallet alerts batch handed to the job after #{attempt} attempts: #{e.class} #{e.message}")
    Sentry.capture_exception(e, extra: {attempts: attempt})
    mark_as_consumed(messages.last)
  end

  private

  # Resolving by organization too skips a payload naming another organization's wallet.
  def resolve(keys)
    Wallet.where(id: keys.map(&:last)).index_by { [it.organization_id, it.id] }.slice(*keys)
  end

  def hand_to_job(wallets)
    wallets.each { UsageMonitoring::ProcessWalletAlertsJob.perform_later(it) }
    report(:deferred, :batch_failed, by: wallets.size)
  end

  def parse(message)
    payload = message.payload # upsert-format retractions arrive as tombstones
    return payload if payload.nil? || payload.is_a?(Hash)

    report(:skipped, :invalid_payload)
    nil
  rescue JSON::ParserError
    report(:skipped, :invalid_payload)
    nil
  end

  def evaluate(wallet, wallet_payloads)
    UsageMonitoring::ProcessWalletAlertsService.call!(wallet:)

    report(:evaluated, :none)
    report_latency(wallet_payloads)
  rescue => e
    # Raising out of #consume would replay the batch, re-evaluating every wallet already done.
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
