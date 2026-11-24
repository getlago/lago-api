# frozen_string_literal: true

RSpec.describe Invoices::Preview::SubscriptionsService do
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
        let(:subscriptions) { create_pair(:subscription, customer:) }

        context "when terminated at is not provided" do
          context "when plan code is present" do
            let(:params) do
              {
                subscriptions: {
                  external_ids:,
                  plan_code: target_plan.code
                }
              }
            end

            let(:target_plan) { create(:plan, organization:, pay_in_advance: true) }

            context "when customer is a new record" do
              let(:customer) { build(:customer, organization:) }
              let(:external_ids) { [SecureRandom.uuid] }

              it "fails with customer not persisted error" do
                expect(result).to be_failure

                expect(result.error.messages).to match(customer: ["must_be_persisted"])
              end
            end

            context "when customer is a persisted record" do
              context "when multiple subscriptions passed" do
                let(:external_ids) { subscriptions.map(&:external_id) }

                it "fails with multiple subscriptions error" do
                  expect(result).to be_failure

                  expect(result.error.messages)
                    .to match(subscriptions: ["only_one_subscription_allowed_for_plan_change"])
                end
              end

              context "when single subscription passed" do
                let(:external_ids) { [subscriptions.first.external_id] }

                before { freeze_time }

                it "returns result with subscriptions marked as terminated and new subscription" do
                  expect(result).to be_success
                  expect(subject).to match_array [subscriptions.first, Subscription]

                  expect(subject.first)
                    .to have_attributes(status: "terminated", terminated_at: Time.current)

                  expect(subject.second)
                    .to be_new_record
                    .and have_attributes(status: "active", started_at: Time.current, name: target_plan.name)
                end
              end
            end
          end

          context "when plan code is missing" do
            let(:params) do
              {
                subscriptions: {
                  external_ids:
                }
              }
            end

            context "when customer is a new record" do
              let(:customer) { build(:customer, organization:) }
              let(:external_ids) { [SecureRandom.uuid] }

              it "fails with customer not persisted error" do
                expect(result).to be_failure

                expect(result.error.messages).to match(customer: ["must_be_persisted"])
              end
            end

            context "when customer is a persisted record" do
              let(:external_ids) { subscriptions.map(&:external_id) }

              it "returns persisted customer subscriptions" do
                expect(result).to be_success
                expect(subject.pluck(:external_id)).to match_array subscriptions.map(&:external_id)
              end
            end
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

          context "when customer is a new record" do
            let(:customer) { build(:customer, organization:) }
            let(:external_ids) { [SecureRandom.uuid] }

            it "fails with customer not persisted error" do
              expect(result).to be_failure

              expect(result.error.messages).to match(customer: ["must_be_persisted"])
            end
          end

          context "when customer is a persisted record" do
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

        context "when subscription is ending" do
          let(:external_ids) { [subscriptions.first.external_id] }
          let(:ending_at) { end_of_period.iso8601 }
          let(:end_of_period) do
            Subscriptions::DatesService
              .new_instance(subscriptions.first, Time.current, current_usage: true)
              .end_of_period
          end
          let(:params) do
            {
              subscriptions: {
                external_ids: external_ids
              }
            }
          end

          before { subscriptions.first.update!(ending_at:) }

          context "with ending_at in current period" do
            it "returns result with subscriptions marked as terminated" do
              expect(result).to be_success

              expect(subject).to all(
                be_a(Subscription)
                  .and(have_attributes(
                    terminated_at: end_of_period.change(usec: 0),
                    status: "terminated"
                  ))
              )
            end
          end

          context "with ending_at in the future" do
            let(:ending_at) { (Time.current + 5.months).iso8601 }

            it "returns result with active subscription" do
              expect(result).to be_success

              expect(subject).to all(
                be_a(Subscription)
                  .and(have_attributes(
                    terminated_at: nil,
                    status: "active"
                  ))
              )
            end
          end

          context "without ending_at" do
            let(:ending_at) { nil }

            it "returns result with active subscription" do
              expect(result).to be_success

              expect(subject).to all(
                be_a(Subscription)
                  .and(have_attributes(
                    terminated_at: nil,
                    status: "active"
                  ))
              )
            end
          end
        end

        context "when subscription is pending" do
          let(:pending_subscription) do
            create(
              :subscription,
              customer:,
              status: :pending,
              subscription_at:
            )
          end
          let(:external_ids) { [pending_subscription.external_id] }
          let(:params) do
            {
              subscriptions: {
                external_ids:
              }
            }
          end

          context "when subscription is starting in the future" do
            let(:subscription_at) { Time.current + 2.days }

            it "returns pending subscription for preview" do
              expect(result).to be_success
              expect(subject.size).to eq(1)
              expect(subject.first).to have_attributes(
                status: "active",
                plan_id: pending_subscription.plan_id,
                subscription_at: pending_subscription.subscription_at,
                billing_time: pending_subscription.billing_time,
                customer_id: pending_subscription.customer_id,
                external_id: pending_subscription.external_id
              )
            end
          end

          context "when subscription is not starting in the future" do
            let(:subscription_at) { Time.current - 1.day }

            it "fails with subscription not found error" do
              expect(result).to be_failure
              expect(result.error.error_code).to eq("subscription_not_found")
            end
          end

          context "when subscription_at is exactly now" do
            let(:subscription_at) { Time.current }

            it "fails with subscription not found error" do
              expect(result).to be_failure
              expect(result.error.error_code).to eq("subscription_not_found")
            end
          end

          context "when multiple pending subscriptions with same external_id exist" do
            let(:subscription_at) { Time.current + 2.days }
            let(:external_id) { SecureRandom.uuid }
            let(:external_ids) { [external_id] }

            before do
              create(
                :subscription,
                customer:,
                external_id:,
                status: :pending,
                subscription_at: Time.current + 2.days
              )
              create(
                :subscription,
                customer:,
                external_id:,
                status: :pending,
                subscription_at: Time.current + 3.days
              )
            end

            it "fails with subscription not found error when count is not 1" do
              expect(result).to be_failure
              expect(result.error.error_code).to eq("subscription_not_found")
            end
          end
        end

        context "when several subscriptions including pending ones are passed" do
          let(:active_subscription) { create(:subscription, customer:, created_at: 2.days.ago) }
          let(:pending_subscription) do
            create(:subscription, :pending, customer:, subscription_at: Time.current + 2.days, created_at: 1.day.ago)
          end
          let(:other_pending_subscription) do
            create(:subscription, :pending, customer:, subscription_at: Time.current + 2.days)
          end
          let(:params) { {subscriptions: {external_ids:}} }

          context "with an active and a pending subscription" do
            let(:external_ids) { [pending_subscription.external_id, active_subscription.external_id] }

            it "returns the active subscription and an unsaved active duplicate of the pending one" do
              expect(result).to be_success
              expect(subject.map(&:external_id)).to eq([active_subscription.external_id, pending_subscription.external_id])
              expect(subject.first).to eq(active_subscription)
              expect(subject.second).to be_new_record.and have_attributes(
                status: "active",
                plan_id: pending_subscription.plan_id,
                started_at: pending_subscription.subscription_at,
                created_at: pending_subscription.subscription_at
              )
              expect(pending_subscription.reload).to have_attributes(status: "pending", started_at: nil)
            end
          end

          context "with two pending subscriptions" do
            let(:external_ids) { [other_pending_subscription.external_id, pending_subscription.external_id] }

            it "returns an unsaved active duplicate of each pending subscription" do
              expect(result).to be_success
              expect(subject.map(&:external_id))
                .to eq([pending_subscription.external_id, other_pending_subscription.external_id])
              expect(subject).to all(be_new_record.and(have_attributes(status: "active")))
              expect(subject.map(&:plan_id)).to eq([pending_subscription.plan_id, other_pending_subscription.plan_id])
            end
          end

          context "with a pending subscription that does not start in the future" do
            let(:pending_subscription) { create(:subscription, :pending, customer:, subscription_at: 1.day.ago) }
            let(:external_ids) { [active_subscription.external_id, pending_subscription.external_id] }

            it "returns only the active subscription" do
              expect(result).to be_success
              expect(subject).to eq([active_subscription])
            end
          end

          context "with an external_id that has several standalone pending subscriptions" do
            let(:external_id) { SecureRandom.uuid }
            let(:external_ids) { [active_subscription.external_id, external_id] }

            before do
              create(:subscription, :pending, customer:, external_id:, subscription_at: Time.current + 2.days)
              create(:subscription, :pending, customer:, external_id:, subscription_at: Time.current + 3.days)
            end

            it "returns only the active subscription" do
              expect(result).to be_success
              expect(subject).to eq([active_subscription])
            end
          end

          context "with an active subscription that has a pending next subscription" do
            let(:next_plan) { create(:plan, organization:, amount_cents: active_subscription.plan.amount_cents + 100) }
            let(:external_ids) { [active_subscription.external_id, pending_subscription.external_id] }

            before do
              create(
                :subscription,
                :pending,
                customer:,
                plan: next_plan,
                external_id: active_subscription.external_id,
                previous_subscription: active_subscription,
                subscription_at: Time.current + 2.days
              )
            end

            it "returns the active subscription without duplicating its next subscription" do
              expect(result).to be_success
              expect(subject.size).to eq(2)
              expect(subject.first).to eq(active_subscription)
              expect(subject.second).to be_new_record.and have_attributes(plan_id: pending_subscription.plan_id)
            end
          end

          context "when terminated at is provided" do
            let(:terminated_at) { generate(:future_date) }
            let(:external_ids) { [active_subscription.external_id, pending_subscription.external_id] }
            let(:params) { {subscriptions: {external_ids:, terminated_at: terminated_at.to_s}} }

            it "terminates only the active subscription" do
              expect(result).to be_success
              expect(subject).to eq([active_subscription])
              expect(subject.first).to have_attributes(status: "terminated", terminated_at: terminated_at.change(usec: 0))
            end
          end

          context "when plan code is provided" do
            let(:target_plan) { create(:plan, organization:, pay_in_advance: true) }
            let(:external_ids) { [active_subscription.external_id, pending_subscription.external_id] }
            let(:params) { {subscriptions: {external_ids:, plan_code: target_plan.code}} }

            before { freeze_time }

            it "changes the plan of the active subscription only" do
              expect(result).to be_success
              expect(subject.size).to eq(2)
              expect(subject.first).to eq(active_subscription)
              expect(subject.first).to have_attributes(status: "terminated")
              expect(subject.second).to be_new_record.and have_attributes(plan_id: target_plan.id)
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

        context "when customer is a new record" do
          let(:customer) { build(:customer, organization:) }

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

        context "when customer is a persisted record" do
          let(:customer) { create(:customer, organization:) }

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

        context "when a billing_entity is provided" do
          let(:result) { described_class.call(organization:, customer:, params:, billing_entity:) }
          let(:customer) { create(:customer, organization:) }
          let(:other_billing_entity) { create(:billing_entity, organization:) }

          context "when multi_entity_billing flag is enabled" do
            context "when the billing entity differs from the customer default" do
              let(:billing_entity) { other_billing_entity }

              it "forwards it to the built subscription" do
                expect(result).to be_success
                expect(subject.first.billing_entity_id).to eq(other_billing_entity.id)
              end
            end

            context "when the billing entity matches the customer default" do
              let(:billing_entity) { customer.billing_entity }

              it "leaves the built subscription's billing_entity_id nil" do
                expect(result).to be_success
                expect(subject.first.billing_entity_id).to be_nil
              end
            end
          end
        end
      end
    end
  end
end
