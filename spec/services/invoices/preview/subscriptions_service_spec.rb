# frozen_string_literal: true

RSpec.describe Invoices::Preview::SubscriptionsService, type: :service do
  let(:result) { described_class.call(organization:, customer:, params:) }

  describe ".call" do
    subject { result.subscriptions }

    context "when organization is missing" do
      let(:organization) { nil }
      let(:customer) { nil }
      let(:params) { {} }

      it "fails with organization not found error" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("organization_not_found")
      end
    end

    context "when customer is missing" do
      let(:organization) { create(:organization) }
      let(:customer) { nil }
      let(:params) { {} }

      it "fails with customer not found error" do
        expect(result).to be_failure
        expect(result.error.error_code).to eq("customer_not_found")
      end
    end

    context "when customer and organization are present" do
      let(:organization) { create(:organization) }
      let(:customer) { create(:customer, organization:) }

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
            expect(result).to be_success
            expect(subject.pluck(:external_id)).to match_array subscriptions.map(&:external_id)
          end
        end

        context "when terminated at is provided" do
          let(:terminated_at) { generate(:future_date) }

          let(:params) do
            {
              subscriptions: {
                external_ids: external_ids,
                terminated_at: terminated_at.to_s
              }
            }
          end

          context "when multiple subscriptions passed" do
            let(:external_ids) { subscriptions.map(&:external_id) }

            it "fails with multiple subscriptions error" do
              expect(result).to be_failure

              expect(result.error.messages)
                .to match(subscriptions: ["only_one_subscription_allowed_for_termination"])
            end
          end

          context "when single subscription passed" do
            let(:external_ids) { [subscriptions.first.external_id] }

            it "returns result with subscriptions marked as terminated" do
              expect(result).to be_success

              expect(subject).to all(
                be_a(Subscription)
                  .and(have_attributes(
                    terminated_at: terminated_at.change(usec: 0),
                    status: "terminated"
                  ))
              )
            end
          end
        end
      end

      context "when external_ids are not provided" do
        let(:params) do
          {
            billing_time:,
            plan_code: plan.code,
            subscription_at: subscription_at.iso8601
          }
        end

        let(:plan) { create(:plan, organization:) }
        let(:subscription_at) { generate(:past_date) }
        let(:billing_time) { "anniversary" }

        it "returns new subscription with provided params" do
          expect(result).to be_success
          expect(subject).to contain_exactly Subscription

          expect(subject.first)
            .to be_new_record
            .and have_attributes(
              customer:,
              plan:,
              subscription_at: subscription_at.change(usec: 0),
              started_at: subscription_at.change(usec: 0),
              billing_time:
            )
        end
      end
    end
  end
end
