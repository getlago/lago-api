# frozen_string_literal: true

require "pry"

RSpec.describe Invoices::Preview::SubscriptionsService, type: :service do
  let(:result) { described_class.call(organization:, customer:, params:) }

  describe "#call" do
    subject { result.subscriptions }

    let(:organization) { create(:organization) }
    let(:customer) { create(:customer, organization:) }

    context "when customer is missing" do
      let(:customer) { nil }
      let(:params) { {} }

      it "returns a failed result with customer not found error" do
        expect(result).not_to be_success
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end

    context "when external_ids are provided" do
      let!(:subscriptions) { create_pair(:subscription, customer:) }
      let(:subscription_ids) { subscriptions.map(&:external_id) }

      context "when terminated at is not provided" do
        let(:params) do
          {
            subscriptions: {
              external_ids: subscriptions.map(&:external_id)
            }
          }
        end

        it "returns persisted customer subscriptions" do
          expect(subject.pluck(:external_id)).to match_array subscriptions.map(&:external_id)
        end
      end

      context "when terminated at is provided" do
        let(:external_ids) { [subscriptions.first.external_id] }
        let(:terminated_at) { generate(:future_date) }

        let(:params) do
          {
            subscriptions: {
              external_ids: external_ids,
              terminated_at: terminated_at.to_s
            }
          }
        end

        context "when invalid timestamp provided" do
          let(:terminated_at) { "2025" }

          it "returns a failed result with invalid timestamp error" do
            expect(result).not_to be_success
            expect(result.error.messages).to match(terminated_at: ["invalid_timestamp"])
          end
        end

        context "when past timestamp provided" do
          let(:terminated_at) { generate(:past_date) }

          it "returns a failed result with past timestamp error" do
            expect(result).not_to be_success
            expect(result.error.messages).to match(terminated_at: ["cannot_be_in_past"])
          end
        end

        context "when multiple subscriptions passed" do
          let(:external_ids) { subscriptions.map(&:external_id) }

          it "returns a failed result with multiple subscriptions error" do
            expect(result).not_to be_success

            expect(result.error.messages)
              .to match(subscriptions: ["only_one_subscription_allowed_for_termination"])
          end
        end

        context "when all validations passed" do
          it "returns result with subscriptions marked as terminated" do
            expect(subject).to all(
              be_a(Subscription)
                .and(have_attributes(terminated_at: terminated_at.change(usec: 0)))
            )
          end
        end
      end
    end

    context "when external_ids are not provided" do
      let(:params) do
        {
          billing_time:,
          plan_code: plan&.code,
          subscription_at: subscription_at&.iso8601
        }
      end

      context "when plan matching provided code exists" do
        let(:plan) { create(:plan, organization:) }

        before { freeze_time }

        context "when billing time and subscription date are present" do
          let(:subscription_at) { generate(:past_date) }
          let(:billing_time) { "anniversary" }

          it "returns new subscription with provided params" do
            expect(subject)
              .to all(
                be_a(Subscription)
                  .and(have_attributes(
                    customer:,
                    plan:,
                    subscription_at: subscription_at,
                    started_at: subscription_at,
                    billing_time: params[:billing_time]
                  ))
              )
          end
        end

        context "when billing time and subscription date are missing" do
          let(:subscription_at) { nil }
          let(:billing_time) { nil }

          it "returns new subscription with default values for subscription date and billing time" do
            expect(subject)
              .to all(
                be_a(Subscription)
                  .and(have_attributes(
                    customer:,
                    plan:,
                    subscription_at: Time.current,
                    started_at: Time.current,
                    billing_time: "calendar"
                  ))
              )
          end
        end
      end

      context "when plan matching provided code does not exist" do
        let(:plan) { nil }
        let(:subscription_at) { nil }
        let(:billing_time) { nil }

        it "returns nil" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq("plan_not_found")

          expect(subject).to be_nil
        end
      end
    end
  end
end
