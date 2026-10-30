# frozen_string_literal: true

module UsageMonitoring
  # WalletAlertsConsumer evaluates off the Sidekiq queues, which lag behind the realtime refresh.
  class DispatchWalletAlertsService < BaseService
    Result = BaseResult

    def initialize(wallet:)
      @wallet = wallet
      super
    end

    def call
      return result unless License.premium?

      # Evaluation reads the wallet back from the database, so it must not run before the commit. The
      # alert check runs there too, off the caller's transaction (once per fee on invoice finalization).
      after_commit { dispatch if wallet.alerts.using_wallet.exists? }

      result
    end

    private

    attr_reader :wallet

    def dispatch
      if kafka? && produce
        report(:kafka)
      else
        # A failed produce has been logged: the job keeps the evaluation.
        ProcessWalletAlertsJob.perform_later(wallet)
        report(kafka? ? :job_fallback : :job)
      end
    end

    # The lane follows the realtime wallet refresh: off it, the ongoing balance is only as fresh as
    # the refresh sweep, which the job keeps up with.
    def kafka?
      return @kafka if defined?(@kafka)

      @kafka = topic.present? && RealtimeUsage.enabled?(wallet.organization)
    end

    def produce
      Utils::KafkaProducer.produce_async(
        topic:,
        # Keyed by wallet, so the consumer evaluates one wallet's messages in order.
        key: wallet.id,
        payload: {
          organization_id: wallet.organization_id,
          wallet_id: wallet.id,
          dispatched_at_ms: (Time.current.to_f * 1000).to_i
        }.to_json
      )
    rescue WaterDrop::Errors::MessageInvalidError, WaterDrop::Errors::ProduceError => e
      # Without SENTRY_DSN the producer re-raises: this runs after the commit, so raising would turn a
      # saved balance into a 500 and lose the evaluation.
      Rails.logger.error("[alerts] wallet alerts produce failed wallet_id=#{wallet.id}: #{e.class} #{e.message}")
      false
    end

    def topic
      ENV["LAGO_KAFKA_WALLET_ALERTS_TOPIC"]
    end

    def report(via)
      Yabeda.usage_monitoring.wallet_alerts_dispatched_total.increment({via: via.to_s})
    end
  end
end
