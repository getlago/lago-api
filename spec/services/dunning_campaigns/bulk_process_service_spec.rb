# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::BulkProcessService, aggregate_failures: true do
  subject(:result) { described_class.call }

  let(:currency) { "EUR" }

  context "when premium features are enabled" do
    let(:organization) { create :organization, premium_integrations: %w[auto_dunning] }
    let(:billing_entity) { organization.default_billing_entity }
    let(:customer) { create :customer, organization:, billing_entity:, currency: }

    let(:invoice_1) do
      create(
        :invoice,
        organization:,
        customer:,
        currency:,
        payment_overdue: true,
        total_amount_cents: 50_00
      )
    end

    let(:invoice_2) do
      create(
        :invoice,
        organization:,
        customer:,
        currency:,
        payment_overdue: true,
        total_amount_cents: 1_00
      )
    end

    around { |test| lago_premium!(&test) }

    context "when billing_entity has an applied dunning campaign" do
      let(:dunning_campaign) { create :dunning_campaign, organization: }

      let(:dunning_campaign_threshold) do
        create(
          :dunning_campaign_threshold,
          dunning_campaign:,
          currency:,
          amount_cents: 50_99
        )
      end

      before do
        dunning_campaign
        dunning_campaign_threshold
        billing_entity.update!(applied_dunning_campaign: dunning_campaign)
      end

      context "when a customer has overdue balance exceeding threshold in same currency" do
        before do
          invoice_1
          invoice_2
        end

        it "enqueues an ProcessAttemptJob with the customer and threshold" do
          expect(result).to be_success
          expect(DunningCampaigns::ProcessAttemptJob)
            .to have_been_enqueued
            .with(customer:, dunning_campaign_threshold:)
        end

        context "when organization does not have auto_dunning feature enabled" do
          let(:organization) { create(:organization, premium_integrations: []) }

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end

        context "when maximum attempts are reached" do
          let(:customer) { create :customer, organization:, billing_entity:, last_dunning_campaign_attempt: 5 }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              max_attempts: 5
            )
          end

          before { billing_entity.update!(applied_dunning_campaign: dunning_campaign) }

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end

          context "with overdue balance greater than zero" do
            it "sends valid webhook" do
              expect { result }.to have_enqueued_job(SendWebhookJob).with("dunning_campaign.finished", customer, {dunning_campaign_code: dunning_campaign.code})
            end
          end
        end

        context "when not enough days have passed since last attempt" do
          let(:customer) { create :customer, organization:, billing_entity:, last_dunning_campaign_attempt_at: 3.days.ago }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              days_between_attempts: 4
            )
          end

          before { billing_entity.update!(applied_dunning_campaign: dunning_campaign) }

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end

        context "when enough days have passed since last attempt" do
          let(:customer) { create :customer, organization:, billing_entity:, last_dunning_campaign_attempt_at: 4.days.ago - 1.second }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              days_between_attempts: 4
            )
          end

          before { billing_entity.update!(applied_dunning_campaign: dunning_campaign) }

          it "enqueues an ProcessAttemptJob with the customer and threshold" do
            expect(result).to be_success
            expect(DunningCampaigns::ProcessAttemptJob)
              .to have_been_enqueued
              .with(customer:, dunning_campaign_threshold:)
          end
        end
      end

      context "when customer has overdue balance below threshold" do
        before do
          invoice_1
        end

        it "does not queue a job for the customer" do
          result
          expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
        end
      end

      context "when there is no matching threshold for customer overdue balance" do
        let(:dunning_campaign_threshold) do
          create(
            :dunning_campaign_threshold,
            dunning_campaign:,
            currency: "GBP",
            amount_cents: 1
          )
        end

        before do
          invoice_1
        end

        it "does not queue a job for the customer" do
          result
          expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
        end
      end

      context "when customer has an applied dunning campaign overwriting billing entity's default campaign" do
        let(:customer) do
          create(
            :customer,
            organization:,
            billing_entity:,
            currency:,
            applied_dunning_campaign: customer_dunning_campaign
          )
        end

        let(:customer_dunning_campaign) do
          create(:dunning_campaign, organization:)
        end

        let(:customer_dunning_campaign_threshold) do
          create(
            :dunning_campaign_threshold,
            dunning_campaign: customer_dunning_campaign,
            currency:,
            amount_cents: 49_99
          )
        end

        before do
          customer_dunning_campaign
          customer_dunning_campaign_threshold
        end

        context "when a customer has overdue balance exceeding threshold in same currency" do
          before do
            invoice_1
          end

          it "enqueues an ProcessAttemptJob with the customer and customer's campaign threshold" do
            expect(result).to be_success
            expect(DunningCampaigns::ProcessAttemptJob)
              .to have_been_enqueued
              .with(customer:, dunning_campaign_threshold: customer_dunning_campaign_threshold)
          end
        end

        context "when customer has overdue balance below threshold" do
          before do
            invoice_2
          end

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end

        context "when there is no matching threshold for customer overdue balance" do
          let(:customer_dunning_campaign_threshold) do
            create(
              :dunning_campaign_threshold,
              dunning_campaign:,
              currency: "GBP",
              amount_cents: 1
            )
          end

          before do
            invoice_1
          end

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end
      end

      context "when customer is excluded from dunning campaigns" do
        let(:customer) { create :customer, organization:, billing_entity:, currency:, exclude_from_dunning_campaign: true }

        context "when a customer has overdue balance exceeding threshold in same currency" do
          before do
            invoice_1
            invoice_2
          end

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end
      end
    end

    context "when customer has an applied dunning campaign" do
      let(:customer) do
        create(
          :customer,
          organization:,
          billing_entity:,
          currency:,
          applied_dunning_campaign: dunning_campaign
        )
      end

      let(:dunning_campaign) do
        create(:dunning_campaign, organization:)
      end

      let(:dunning_campaign_threshold) do
        create(
          :dunning_campaign_threshold,
          dunning_campaign:,
          currency:,
          amount_cents: 49_99
        )
      end

      before do
        dunning_campaign
        dunning_campaign_threshold
      end

      context "when a customer has overdue balance exceeding threshold in same currency" do
        before do
          invoice_1
        end

        it "enqueues an ProcessAttemptJob with the customer and customer's campaign threshold" do
          expect(result).to be_success
          expect(DunningCampaigns::ProcessAttemptJob)
            .to have_been_enqueued
            .with(customer:, dunning_campaign_threshold:)
        end

        context "when organization does not have auto_dunning feature enabled" do
          let(:organization) { create(:organization, premium_integrations: []) }

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end

        context "when maximum attempts are reached" do
          let(:customer) { create :customer, organization:, billing_entity:, last_dunning_campaign_attempt: 5 }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              max_attempts: 5
            )
          end

          before { billing_entity.update!(applied_dunning_campaign: dunning_campaign) }

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end

        context "when not enough days have passed since last attempt" do
          let(:customer) { create :customer, organization:, billing_entity:, last_dunning_campaign_attempt_at: 3.days.ago }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              days_between_attempts: 4
            )
          end

          before { billing_entity.update!(applied_dunning_campaign: dunning_campaign) }

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end

        context "when enough days have passed since last attempt" do
          let(:customer) { create :customer, organization:, billing_entity:, last_dunning_campaign_attempt_at: 4.days.ago - 1.second }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              days_between_attempts: 4
            )
          end

          before { billing_entity.update!(applied_dunning_campaign: dunning_campaign) }

          it "enqueues an ProcessAttemptJob with the customer and threshold" do
            expect(result).to be_success
            expect(DunningCampaigns::ProcessAttemptJob)
              .to have_been_enqueued
              .with(customer:, dunning_campaign_threshold:)
          end
        end
      end

      context "when customer has overdue balance below threshold" do
        before do
          invoice_2
        end

        it "does not queue a job for the customer" do
          result
          expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
        end
      end

      context "when there is no matching threshold for customer overdue balance" do
        let(:dunning_campaign_threshold) do
          create(
            :dunning_campaign_threshold,
            dunning_campaign:,
            currency: "GBP",
            amount_cents: 1
          )
        end

        before do
          invoice_1
        end

        it "does not queue a job for the customer" do
          result
          expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
        end
      end
    end

    context "when neither billing_entity nor customer has an applied dunning campaign" do
      let(:dunning_campaign) { create :dunning_campaign, organization: }

      let(:dunning_campaign_threshold) do
        create(
          :dunning_campaign_threshold,
          dunning_campaign:,
          currency:,
          amount_cents: 1
        )
      end

      before do
        dunning_campaign_threshold
        invoice_1
      end

      it "does not queue a job for the customer" do
        result
        expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
      end
    end

    context "when organization has multiple billing entities with different applied dunning campaigns" do
      let(:billing_entity_1) { create :billing_entity, organization:, applied_dunning_campaign: dunning_campaign_1 }
      let(:billing_entity_2) { create :billing_entity, organization:, applied_dunning_campaign: dunning_campaign_2 }
      let(:customer_1) { create :customer, organization:, billing_entity: billing_entity_1, currency: }
      let(:customer_2) { create :customer, organization:, billing_entity: billing_entity_2, currency: }
      let(:customer_3) { create :customer, organization:, billing_entity: billing_entity, currency:, applied_dunning_campaign: dunning_campaign_1 }

      let(:dunning_campaign_1) { create :dunning_campaign, organization: }
      let(:dunning_campaign_2) { create :dunning_campaign, organization: }

      let(:dunning_campaign_threshold_1) do
        create(
          :dunning_campaign_threshold,
          dunning_campaign: dunning_campaign_1,
          currency:,
          amount_cents: 50_99
        )
      end

      let(:dunning_campaign_threshold_2) do
        create(
          :dunning_campaign_threshold,
          dunning_campaign: dunning_campaign_2,
          currency:,
          amount_cents: 49_99
        )
      end

      before do
        dunning_campaign_threshold_1
        dunning_campaign_threshold_2
      end

      context "when all customers have overdue balances exceeding all thresholds" do
        before do
          create(:invoice, organization:, customer: customer, currency:, payment_overdue: true, total_amount_cents: 100_00)
          create(:invoice, organization:, customer: customer_1, currency:, payment_overdue: true, total_amount_cents: 60_00)
          create(:invoice, organization:, customer: customer_2, currency:, payment_overdue: true, total_amount_cents: 51_00)
          create(:invoice, organization:, customer: customer_3, currency:, payment_overdue: true, total_amount_cents: 51_00)
        end

        it "enqueues ProcessAttemptJob for both customers with their respective thresholds" do
          expect(result).to be_success
          expect(DunningCampaigns::ProcessAttemptJob)
            .not_to have_been_enqueued.with(hash_including(customer: customer))
          expect(DunningCampaigns::ProcessAttemptJob)
            .to have_been_enqueued.with(customer: customer_1, dunning_campaign_threshold: dunning_campaign_threshold_1)
          expect(DunningCampaigns::ProcessAttemptJob)
            .to have_been_enqueued.with(customer: customer_2, dunning_campaign_threshold: dunning_campaign_threshold_2)
          expect(DunningCampaigns::ProcessAttemptJob)
            .to have_been_enqueued.with(customer: customer_3, dunning_campaign_threshold: dunning_campaign_threshold_1)
        end
      end
    end
  end

  it "does not queue jobs" do
    result
    expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
  end
end
