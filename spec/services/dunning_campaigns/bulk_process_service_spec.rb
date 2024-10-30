# frozen_string_literal: true

require "rails_helper"

RSpec.describe DunningCampaigns::BulkProcessService, type: :service, aggregate_failures: true do
  subject(:result) { described_class.call }

  let(:currency) { "EUR" }

  context "when premium features are enabled" do
    let(:organization) { create :organization, premium_integrations: %w[auto_dunning] }
    let(:customer) { create :customer, organization:, currency: }

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

    context "when organization has an applied dunning campaign" do
      let(:dunning_campaign) { create :dunning_campaign, organization:, applied_to_organization: true }

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
          let(:customer) { create :customer, organization:, last_dunning_campaign_attempt: 5 }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              max_attempts: 5,
              applied_to_organization: true
            )
          end

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end

        context "when not enough days have passed since last attempt" do
          let(:customer) { create :customer, organization:, last_dunning_campaign_attempt_at: 3.days.ago }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              days_between_attempts: 4,
              applied_to_organization: true
            )
          end

          it "does not queue a job for the customer" do
            result
            expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
          end
        end

        context "when enough days have passed since last attempt" do
          let(:customer) { create :customer, organization:, last_dunning_campaign_attempt_at: 4.days.ago - 1.second }

          let(:dunning_campaign) do
            create(
              :dunning_campaign,
              organization:,
              days_between_attempts: 4,
              applied_to_organization: true
            )
          end

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

      context "when customer has an applied dunning campaign overwriting organization's default campaign" do
        let(:customer) do
          create(
            :customer,
            organization:,
            currency:,
            applied_dunning_campaign: customer_dunning_campaign
          )
        end

        let(:customer_dunning_campaign) do
          create(:dunning_campaign, organization:, applied_to_organization: false)
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

        context "when overdue balance currency does not match threshold currency" do
          it "does not queue a job for the customer"
        end

        context "when customer has overdue balance below threshold" do
          it "does not queue a job for the customer"
        end
      end

      context "when customer is excluded from dunning campaigns" do
        context "when a customer has overdue balance exceeding threshold in same currency" do
          it "does not queue a job for the customer"
        end
      end
    end

    context "when customer has an applied dunning campaign" do
      context "when a customer has overdue balance exceeding threshold in same currency" do
        it "enqueues an ProcessAttemptJob with the customer and customer's campaign threshold"
      end

      context "when overdue balance currency does not match threshold currency" do
        let(:dunning_campaign_threshold) do
          create(
            :dunning_campaign_threshold,
            dunning_campaign:,
            currency:,
            amount_cents: 100_00
          )
        end

        xit "does not queue a job for the customer" do
          result
          expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
        end
      end
    end

    context "when neither organizaiton nor customer has an applied dunning campaign" do
      it "does not queue a job for the customer"
    end
  end

  it "does not queue jobs" do
    result
    expect(DunningCampaigns::ProcessAttemptJob).not_to have_been_enqueued
  end
end
