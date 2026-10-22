# frozen_string_literal: true

module UsageMonitoring
  # Hands a wallet whose balance moved to alert evaluation. With the wallet alerts topic configured,
  # WalletAlertsConsumer evaluates it as soon as the message lands, off the Sidekiq queues; without
  # it (self-hosted without Kafka) ProcessWalletAlertsJob does, as before.
  class DispatchWalletAlertsService < BaseService
    Result = BaseResult

    def initialize(wallet:)
      @wallet = wallet
      super
    end

    def call
      return result unless License.premium?
      # Every refresh lands here and most wallets carry no alert: this saves a message or a job each.
      return result unless wallet.alerts.using_wallet.exists?

      # Evaluation reads the wallet back from the database, so it must not run before the commit.
      after_commit { dispatch }

      result
    end

    private

    attr_reader :wallet

    def dispatch
      if topic.blank?
        ProcessWalletAlertsJob.perform_later(wallet)
        report(:job)
      elsif produce
        report(:kafka)
      else
        # The producer already reported the error: the job keeps the evaluation from being lost.
        ProcessWalletAlertsJob.perform_later(wallet)
        report(:job_fallback)
      end
    end

    def produce
      Utils::KafkaProducer.produce_async(
        topic:,
        # Keyed by wallet: one wallet's alerts are never evaluated twice at once.
        key: wallet.id,
        payload: {
          organization_id: wallet.organization_id,
          wallet_id: wallet.id,
          dispatched_at_ms: (Time.current.to_f * 1000).to_i
        }.to_json
      )
    end

    def topic
      ENV["LAGO_KAFKA_WALLET_ALERTS_TOPIC"]
    end

    def report(via)
      Yabeda.usage_monitoring.wallet_alerts_dispatched_total.increment({via: via.to_s})
    end
  end
end
