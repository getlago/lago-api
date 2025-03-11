# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::Preview::BuildSubscriptionService, type: :service do
  describe ".call" do
    subject(:result) { described_class.call(customer:, params:) }

    let(:subscriptions) { result.subscriptions }

    context "when customer is missing" do
      let(:customer) { nil }
      let(:params) { {} }

      it "fails with customer not found error" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("customer_not_found")
      end

      it "does not create any subscription" do
        expect { subject }.not_to change(Subscription, :count)
      end
    end

    context "when customer is present" do
      let(:customer) { create(:customer) }

      context "when plan matching code exists in the customer's organization" do
        let(:plan) { create(:plan, organization: customer.organization) }

        let(:params) do
          {
            plan_code: plan&.code,
            billing_time:,
            subscription_at: subscription_at&.iso8601
          }
        end

        context "when valid billing time and subscribed at are provided" do
          let(:billing_time) { Subscription::BILLING_TIME.sample.to_s }
          let(:subscription_at) { generate(:past_date) }

          let(:expected_attributes) do
            {
              billing_time:,
              plan:,
              customer:,
              subscription_at: subscription_at.change(usec: 0),
              started_at: subscription_at.change(usec: 0)
            }
          end

          it "returns array containing new subscription with provided inputs" do
            expect(result).to be_success
            expect(subscriptions).to contain_exactly Subscription

            expect(subscriptions.first)
              .to be_new_record
              .and have_attributes(expected_attributes)
          end

          it "does not create any subscription" do
            expect { subject }.not_to change(Subscription, :count)
          end
        end

        context "when invalid or empty billing time and subscribed at are provided" do
          let(:billing_time) { "non-existing-time" }
          let(:subscription_at) { nil }

          let(:expected_attributes) do
            {
              billing_time: "calendar",
              plan:,
              customer:,
              subscription_at: Time.current,
              started_at: Time.current
            }
          end

          before { freeze_time }

          it "returns array containing new subscription with defaults" do
            expect(result).to be_success
            expect(subscriptions).to contain_exactly Subscription

            expect(subscriptions.first)
              .to be_new_record
              .and have_attributes(expected_attributes)
          end

          it "does not create any subscription" do
            expect { subject }.not_to change(Subscription, :count)
          end
        end
      end

      context "when plan matching code does not exist in the customer's organization" do
        let(:params) { {plan_code: create(:plan).code} }

        it "fails with plan not found error" do
          expect(result).to be_failure
          expect(result.error.error_code).to eq("plan_not_found")
        end

        it "does not create any subscription" do
          expect { subject }.not_to change(Subscription, :count)
        end
      end
    end
  end
end
