# frozen_string_literal: true

require "rails_helper"

RSpec.describe UsageMonitoring::DispatchWalletAlertsService do
  subject(:result) { described_class.call(wallet:) }

  include_context "with realtime usage availability"

  let_it_be(:organization) { create(:organization, clickhouse_events_store: true, feature_flags: ["realtime_usage"]) }
  let_it_be(:customer) { create(:customer, organization:) }
  let_it_be(:wallet) { create(:wallet, organization:, customer:) }

  let(:topic) { nil }
  let(:dispatched) { Yabeda.usage_monitoring.wallet_alerts_dispatched_total }

  before do
    stub_const("ENV", ENV.to_h.merge("LAGO_KAFKA_WALLET_ALERTS_TOPIC" => topic))
    allow(dispatched).to receive(:increment)
  end

  context "when premium", :premium do
    context "when the wallet has an alert" do
      before { create(:wallet_ongoing_balance_amount_alert, organization:, wallet:) }

      it "enqueues the alerts job" do
        expect { result }.to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob).with(wallet)
        expect(karafka.produced_messages).to be_empty
        expect(dispatched).to have_received(:increment).with({via: "job"})
      end

      context "with the wallet alerts topic" do
        let(:topic) { "wallet_alerts" }

        it "produces the wallet on the topic instead of enqueuing a job" do
          freeze_time do
            expect { result }.not_to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob)

            expect(karafka.produced_messages).to eq([
              {
                topic: "wallet_alerts",
                key: wallet.id,
                payload: {
                  organization_id: organization.id,
                  wallet_id: wallet.id,
                  dispatched_at_ms: (Time.current.to_f * 1000).to_i
                }.to_json
              }
            ])
            expect(dispatched).to have_received(:increment).with({via: "kafka"})
          end
        end

        context "when the message cannot be produced" do
          before { allow(Utils::KafkaProducer).to receive(:produce_async).and_return(false) }

          it "falls back to the alerts job" do
            expect { result }.to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob).with(wallet)
            expect(dispatched).to have_received(:increment).with({via: "job_fallback"})
          end
        end

        context "when the producer raises" do
          before do
            allow(Karafka.producer).to receive(:produce_async).and_raise(WaterDrop::Errors::ProduceError)
            stub_const("ENV", ENV.to_h.merge("LAGO_KAFKA_WALLET_ALERTS_TOPIC" => topic, "SENTRY_DSN" => nil))
          end

          it "falls back to the alerts job" do
            expect { result }.to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob).with(wallet)
            expect(dispatched).to have_received(:increment).with({via: "job_fallback"})
          end
        end

        context "when the organization does not have the realtime usage flag" do
          subject(:result) { described_class.call(wallet: other_wallet) }

          let(:other_organization) { create(:organization, clickhouse_events_store: true) }
          let(:other_wallet) { create(:wallet, organization: other_organization, customer: create(:customer, organization: other_organization)) }

          before { create(:wallet_ongoing_balance_amount_alert, organization: other_organization, wallet: other_wallet) }

          it "enqueues the alerts job" do
            expect { result }.to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob).with(other_wallet)
            expect(karafka.produced_messages).to be_empty
            expect(dispatched).to have_received(:increment).with({via: "job"})
          end
        end

        context "when called inside a transaction" do
          it "produces once the transaction commits" do
            ApplicationRecord.transaction do
              described_class.call(wallet:)

              expect(karafka.produced_messages).to be_empty
            end

            expect(karafka.produced_messages.size).to eq(1)
          end
        end
      end
    end

    context "when the wallet alert is deleted" do
      let(:topic) { "wallet_alerts" }

      before { create(:wallet_ongoing_balance_amount_alert, organization:, wallet:).discard! }

      it "dispatches nothing" do
        expect { result }.not_to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob)
        expect(karafka.produced_messages).to be_empty
      end
    end

    context "when the wallet has no alert" do
      let(:topic) { "wallet_alerts" }

      it "dispatches nothing" do
        expect { result }.not_to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob)
        expect(karafka.produced_messages).to be_empty
        expect(dispatched).not_to have_received(:increment)
      end
    end
  end

  context "when freemium" do
    let(:premium_license) { false }

    before { create(:wallet_ongoing_balance_amount_alert, organization:, wallet:) }

    it "dispatches nothing" do
      expect { result }.not_to have_enqueued_job(UsageMonitoring::ProcessWalletAlertsJob)
      expect(karafka.produced_messages).to be_empty
    end
  end
end
