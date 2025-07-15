# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::PreviewService, type: :service, cache: :memory do
  subject(:preview_service) { described_class.new(customer:, subscriptions:) }

  describe "#call" do
    let(:organization) { create(:organization) }
    let(:billing_entity) { create(:billing_entity, organization:) }
    let(:tax) { create(:tax, :applied_to_billing_entity, rate: 50.0, organization:, billing_entity:) }
    let(:customer) { build(:customer, organization:, billing_entity:) }
    let(:timestamp) { Time.zone.parse("30 Mar 2024") }
    let(:plan) { create(:plan, organization:, interval: "monthly") }
    let(:billing_time) { "calendar" }
    let(:subscriptions) { [subscription] }
    let(:subscription) do
      build(
        :subscription,
        customer:,
        plan:,
        billing_time:,
        subscription_at: timestamp,
        started_at: timestamp,
        created_at: timestamp
      )
    end

    before { tax }

    context "with Lago freemium" do
      it "returns a failure" do
        travel_to(timestamp) do
          result = preview_service.call

          expect(result).not_to be_success

          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("feature_unavailable")
        end
      end
    end

    context "with Lago premium" do
      around { |test| lago_premium!(&test) }

      context "when customer does not exist" do
        let(:customer) { nil }

        it "returns a failure" do
          travel_to(timestamp) do
            result = preview_service.call

            expect(result).to be_failure
            expect(result.error.error_code).to eq("customer_not_found")
          end
        end
      end

      context "when subscriptions are missing" do
        let(:subscriptions) { [] }

        it "returns an error" do
          travel_to(timestamp) do
            result = preview_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.resource).to eq("subscription")
          end
        end
      end

      context "when currencies do not match" do
        let(:plan) { create(:plan, organization:, interval: "monthly", amount_currency: "USD") }
        let(:customer) { build(:customer, organization:, billing_entity:, currency: "EUR") }

        it "returns an error" do
          travel_to(timestamp) do
            result = preview_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::SingleValidationFailure)
            expect(result.error.code).to eq("customer_currency_does_not_match")
          end
        end
      end

      context "when billing periods do not match" do
        let(:plan1) { create(:plan, organization:, interval: "monthly") }
        let(:plan2) { create(:plan, organization:, interval: "monthly") }
        let(:subscription1) do
          build(
            :subscription,
            customer:,
            plan: plan1,
            billing_time:,
            subscription_at: timestamp,
            started_at: timestamp,
            created_at: timestamp
          )
        end
        let(:subscription2) do
          build(
            :subscription,
            customer:,
            plan: plan2,
            billing_time:,
            subscription_at: timestamp + 1.day,
            started_at: timestamp + 1.day,
            created_at: timestamp + 1.day
          )
        end
        let(:subscriptions) { [subscription1, subscription2] }

        it "returns an error" do
          travel_to(timestamp) do
            result = preview_service.call

            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::SingleValidationFailure)
            expect(result.error.code).to eq("billing_periods_does_not_match")
          end
        end
      end

      context "with calendar billing" do
        it "creates preview invoice for 2 days" do
          # Two days should be billed, Mar 30 and Mar 31

          travel_to(timestamp) do
            result = preview_service.call

            expect(result).to be_success
            expect(result.invoice.organization).to eq(organization)
            expect(result.invoice.billing_entity).to eq(customer.billing_entity)
            expect(result.invoice.subscriptions.first).to eq(subscription)
            expect(result.invoice.fees.length).to eq(1)
            expect(result.invoice.invoice_type).to eq("subscription")
            expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
            expect(result.invoice.fees_amount_cents).to eq(6)
            expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
            expect(result.invoice.taxes_amount_cents).to eq(3)
            expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(9)
            expect(result.invoice.total_amount_cents).to eq(9)
          end
        end

        context "with fixed charges" do
          let(:add_on) { create(:add_on, organization:) }
          let(:fixed_charge) { create(:fixed_charge, plan:, add_on:, properties: { amount: "10" }) }

          before { fixed_charge }

          it "includes fixed charges in preview invoice" do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.fees.length).to eq(2) # subscription fee + fixed charge fee
              
              fixed_charge_fee = result.invoice.fees.find { |fee| fee.fee_type == "fixed_charge" }
              expect(fixed_charge_fee).to be_present
              expect(fixed_charge_fee.amount_cents).to eq(1000) # 10.00 in cents
              expect(fixed_charge_fee.fixed_charge).to eq(fixed_charge)
            end
          end
        end

        context "with one persisted subscription" do
          let(:customer) { create(:customer, organization:, billing_entity:) }
          let(:subscription) do
            create(
              :subscription,
              customer:,
              plan:,
              billing_time:,
              subscription_at: timestamp,
              started_at: timestamp,
              created_at: timestamp
            )
          end

          before { organization.update!(premium_integrations: ["preview"]) }

          it "creates preview invoice for 2 days" do
            # Two days should be billed, Mar 30 and Mar 31

            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.organization).to eq(organization)
              expect(result.invoice.billing_entity).to eq(customer.billing_entity)
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.invoice_type).to eq("subscription")
              expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
              expect(result.invoice.fees_amount_cents).to eq(6)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
              expect(result.invoice.taxes_amount_cents).to eq(3)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(9)
              expect(result.invoice.total_amount_cents).to eq(9)
            end
          end

          context "with charge fees" do
            let(:billable_metric) { create(:billable_metric, organization:) }
            let(:charge) do
              create(
                :standard_charge,
                plan:,
                billable_metric:,
                properties: {amount: "10"}
              )
            end
            let(:event) do
              create(
                :event,
                organization:,
                customer:,
                subscription:,
                billable_metric:,
                properties: {value: 5},
                timestamp: timestamp
              )
            end

            before do
              charge
              event
            end

            it "creates preview invoice for 2 days", transaction: false do
              # Two days should be billed, Mar 30 and Mar 31

              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.organization).to eq(organization)
                expect(result.invoice.billing_entity).to eq(customer.billing_entity)
                expect(result.invoice.subscriptions.first).to eq(subscription)
                expect(result.invoice.fees.length).to eq(2)
                expect(result.invoice.invoice_type).to eq("subscription")
                expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
                expect(result.invoice.fees_amount_cents).to eq(2538) # 6.45 + 1266 x 2 = 2538
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(2538)
                expect(result.invoice.taxes_amount_cents).to eq(1269) # 1269
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(3807) # 3807
                expect(result.invoice.total_amount_cents).to eq(3807) # 3807
              end
            end

            it "uses the Rails cache", transaction: false do
              key = [
                "charge-usage",
                Subscriptions::ChargeCacheService::CACHE_KEY_VERSION,
                charge.id,
                subscription.id,
                charge.updated_at.iso8601
              ].join("/")

              expect do
                preview_service.call
              end.to change { Rails.cache.exist?(key) }.from(false).to(true)
            end
          end

          context "when preview premium integration does not exist" do
            before { organization.update!(premium_integrations: []) }

            it "returns an error" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).not_to be_success
                expect(result.error).to be_a(BaseService::NotAllowedFailure)
                expect(result.error.code).to eq("premium_integration_missing")
              end
            end
          end

          context "when subscription is terminated" do
            let(:subscription) do
              create(
                :subscription,
                customer:,
                plan:,
                billing_time:,
                subscription_at: timestamp,
                started_at: timestamp,
                created_at: timestamp,
                terminated_at: timestamp + 1.day
              )
            end

            it "creates preview invoice for 1 day" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.fees_amount_cents).to eq(3)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(3)
                expect(result.invoice.taxes_amount_cents).to eq(2)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(5)
                expect(result.invoice.total_amount_cents).to eq(5)
              end
            end
          end

          context "when subscription is upgraded" do
            let(:new_plan) { create(:plan, organization:, interval: "monthly") }
            let(:new_subscription) do
              create(
                :subscription,
                customer:,
                plan: new_plan,
                billing_time:,
                subscription_at: timestamp + 1.day,
                started_at: timestamp + 1.day,
                created_at: timestamp + 1.day
              )
            end

            before do
              subscription.update!(terminated_at: timestamp + 1.day, next_subscription: new_subscription)
              new_subscription.update!(previous_subscription: subscription)
            end

            it "creates preview invoice for 1 day" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.fees_amount_cents).to eq(3)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(3)
                expect(result.invoice.taxes_amount_cents).to eq(2)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(5)
                expect(result.invoice.total_amount_cents).to eq(5)
              end
            end
          end

          context "when subscription is downgraded" do
            let(:new_plan) { create(:plan, organization:, interval: "monthly") }
            let(:new_subscription) do
              create(
                :subscription,
                customer:,
                plan: new_plan,
                billing_time:,
                subscription_at: timestamp + 1.day,
                started_at: timestamp + 1.day,
                created_at: timestamp + 1.day
              )
            end

            before do
              subscription.update!(terminated_at: timestamp + 1.day, next_subscription: new_subscription)
              new_subscription.update!(previous_subscription: subscription)
            end

            it "creates preview invoice" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.subscriptions.size).to eq(2)
                expect(result.invoice.fees.length).to eq(2)
                expect(result.invoice.invoice_type).to eq("subscription")
                expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
                expect(result.invoice.fees_amount_cents).to eq(147) # 97 (charges) + 50 (new plan) = 147
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(147)
                expect(result.invoice.taxes_amount_cents).to eq(74) # 49 (charges) + 25 (new plan) = 90
                expect(result.invoice.credit_notes_amount_cents).to eq(0)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(221)
                expect(result.invoice.total_amount_cents).to eq(221)
              end
            end
          end
        end

        context "with in advance billing in the future" do
          let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: true) }
          let(:subscription) do
            build(
              :subscription,
              customer:,
              plan:,
              billing_time:,
              subscription_at: timestamp + 1.day,
              started_at: timestamp + 1.day,
              created_at: timestamp + 1.day
            )
          end

          it "creates preview invoice for 1 day" do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.fees_amount_cents).to eq(3)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(3)
              expect(result.invoice.taxes_amount_cents).to eq(2)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(5)
              expect(result.invoice.total_amount_cents).to eq(5)
            end
          end
        end

        context "with in advance billing with persisted subscription" do
          let(:customer) { create(:customer, organization:, billing_entity:) }
          let(:plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: true) }
          let(:subscription) do
            create(
              :subscription,
              customer:,
              plan:,
              billing_time:,
              subscription_at: timestamp - 1.day,
              started_at: timestamp - 1.day,
              created_at: timestamp - 1.day
            )
          end

          before { organization.update!(premium_integrations: ["preview"]) }

          it "creates preview invoice for next invoice" do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.organization).to eq(organization)
              expect(result.invoice.billing_entity).to eq(customer.billing_entity)
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.invoice_type).to eq("subscription")
              expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
              expect(result.invoice.fees_amount_cents).to eq(100)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(100)
              expect(result.invoice.taxes_amount_cents).to eq(50)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(150)
              expect(result.invoice.total_amount_cents).to eq(150)
            end
          end

          context "with terminated subscription" do
            let(:subscription) do
              create(
                :subscription,
                customer:,
                plan:,
                billing_time:,
                subscription_at: timestamp - 1.day,
                started_at: timestamp - 1.day,
                created_at: timestamp - 1.day,
                terminated_at: timestamp
              )
            end

            it "creates preview invoice without subscription fee since it has already been paid" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.fees.length).to eq(0)
                expect(result.invoice.fees_amount_cents).to eq(0)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(0)
                expect(result.invoice.taxes_amount_cents).to eq(0)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(0)
                expect(result.invoice.total_amount_cents).to eq(0)
              end
            end
          end

          context "with upgraded subscription" do
            let(:new_plan) { create(:plan, organization:, interval: "monthly", pay_in_advance: true) }
            let(:new_subscription) do
              create(
                :subscription,
                customer:,
                plan: new_plan,
                billing_time:,
                subscription_at: timestamp,
                started_at: timestamp,
                created_at: timestamp
              )
            end

            before do
              subscription.update!(terminated_at: timestamp, next_subscription: new_subscription)
              new_subscription.update!(previous_subscription: subscription)
            end

            it "creates preview invoice for upgrade case" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.fees_amount_cents).to eq(100)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(100)
                expect(result.invoice.taxes_amount_cents).to eq(50)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(150)
                expect(result.invoice.credits.length).to eq(1)
                expect(result.invoice.credits.first.amount_cents).to eq(9)
                expect(result.invoice.total_amount_cents).to eq(141)
              end
            end
          end

          context "when preview premium integration does not exist" do
            before { organization.update!(premium_integrations: []) }

            it "returns an error" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).not_to be_success
                expect(result.error).to be_a(BaseService::NotAllowedFailure)
                expect(result.error.code).to eq("premium_integration_missing")
              end
            end
          end
        end

        context "with applied coupons" do
          let(:coupon) { create(:coupon, organization:, coupon_type: "percentage", percentage_rate: 10.00) }
          let(:applied_coupon) do
            create(
              :applied_coupon,
              customer:,
              coupon:,
              percentage_rate: 10.00
            )
          end

          before { applied_coupon }

          it "creates preview invoice for 2 days with applied coupons" do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.fees_amount_cents).to eq(6)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(5)
              expect(result.invoice.coupons_amount_cents).to eq(1)
              expect(result.invoice.taxes_amount_cents).to eq(3)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(8)
              expect(result.invoice.total_amount_cents).to eq(8)
            end
          end
        end

        context "with credit note credits" do
          let(:customer) { create(:customer, organization:, billing_entity:) }
          let(:subscription) do
            create(
              :subscription,
              customer:,
              plan:,
              billing_time:,
              subscription_at: timestamp,
              started_at: timestamp,
              created_at: timestamp
            )
          end
          let(:credit_note) do
            create(
              :credit_note,
              organization:,
              customer:,
              invoice: create(:invoice, organization:, customer:),
              balance_amount_cents: 10
            )
          end

          before do
            organization.update!(premium_integrations: ["preview"])
            credit_note
          end

          it "creates preview invoice for 2 days with credits included" do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.fees_amount_cents).to eq(6)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
              expect(result.invoice.taxes_amount_cents).to eq(3)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(9)
              expect(result.invoice.credit_notes_amount_cents).to eq(9)
              expect(result.invoice.total_amount_cents).to eq(0)
            end
          end
        end

        context "with wallet credits" do
          let(:wallet) { build(:wallet, customer:, balance: "0.03", credits_balance: "0.03") }

          before { wallet }

          context "with customer that is not persisted" do
            it "does not apply credits" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.total_amount_cents).to eq(9)
                expect(result.invoice.prepaid_credit_amount_cents).to eq(0)
              end
            end
          end

          context "with customer that is persisted" do
            let(:customer) { create(:customer, organization:, billing_entity:) }
            let(:wallet) { create(:wallet, customer:, balance: "0.03", credits_balance: "0.03") }

            it "applies credits" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.subscriptions.first).to eq(subscription)
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.invoice_type).to eq("subscription")
                expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
                expect(result.invoice.fees_amount_cents).to eq(6)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
                expect(result.invoice.taxes_amount_cents).to eq(3)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(9)
                expect(result.invoice.prepaid_credit_amount_cents).to eq(3)
                expect(result.invoice.total_amount_cents).to eq(6)
              end
            end
          end
        end

        context "with provider taxes" do
          let(:customer) { create(:customer, organization:, billing_entity:) }
          let(:subscription) do
            create(
              :subscription,
              customer:,
              plan:,
              billing_time:,
              subscription_at: timestamp,
              started_at: timestamp,
              created_at: timestamp
            )
          end
          let(:integration_customer) do
            create(
              :integration_customer,
              customer:,
              integration_type: "tax_kind"
            )
          end

          before do
            organization.update!(premium_integrations: ["preview"])
            integration_customer
          end

          context "when there is no error" do
            before do
              stub_request(:post, "https://api.tax_provider.com/taxes")
                .with(
                  body: hash_including(
                    "invoice" => hash_including("currency" => "EUR")
                  )
                )
                .to_return(
                  status: 200,
                  body: {
                    "taxes" => [
                      {
                        "item_key" => "subscription",
                        "tax_amount" => 5.0,
                        "tax_rate" => 50.0
                      }
                    ]
                  }.to_json
                )
            end

            it "creates preview invoice for 2 days" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.fees_amount_cents).to eq(6)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
                expect(result.invoice.taxes_amount_cents).to eq(5)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(11)
                expect(result.invoice.total_amount_cents).to eq(11)
              end
            end
          end

          context "when there is error received from the provider" do
            before do
              stub_request(:post, "https://api.tax_provider.com/taxes")
                .to_return(status: 400, body: "Bad Request")
            end

            it "uses zero taxes" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.fees_amount_cents).to eq(6)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
                expect(result.invoice.taxes_amount_cents).to eq(0)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(6)
                expect(result.invoice.total_amount_cents).to eq(6)
              end
            end
          end

          context "when there is Net::OpenTimeout error" do
            before do
              stub_request(:post, "https://api.tax_provider.com/taxes")
                .to_raise(Net::OpenTimeout)
            end

            it "uses zero taxes" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.fees_amount_cents).to eq(6)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
                expect(result.invoice.taxes_amount_cents).to eq(0)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(6)
                expect(result.invoice.total_amount_cents).to eq(6)
              end
            end
          end
        end
      end

      context "with anniversary billing" do
        let(:billing_time) { "anniversary" }

        it "creates preview invoice for full month" do
          travel_to(timestamp) do
            result = preview_service.call

            expect(result).to be_success
            expect(result.invoice.fees.length).to eq(1)
            expect(result.invoice.fees_amount_cents).to eq(100)
            expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(100)
            expect(result.invoice.taxes_amount_cents).to eq(50)
            expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(150)
            expect(result.invoice.total_amount_cents).to eq(150)
          end
        end

        context "with one persisted subscriptions" do
          let(:customer) { create(:customer, organization:, billing_entity:) }
          let(:subscription) do
            create(
              :subscription,
              customer:,
              plan:,
              billing_time:,
              subscription_at: timestamp,
              started_at: timestamp,
              created_at: timestamp
            )
          end

          before { organization.update!(premium_integrations: ["preview"]) }

          it "creates preview invoice for full month" do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.organization).to eq(organization)
              expect(result.invoice.billing_entity).to eq(customer.billing_entity)
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.invoice_type).to eq("subscription")
              expect(result.invoice.issuing_date.to_s).to eq("2024-04-30")
              expect(result.invoice.fees_amount_cents).to eq(100)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(100)
              expect(result.invoice.taxes_amount_cents).to eq(50)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(150)
              expect(result.invoice.total_amount_cents).to eq(150)
            end
          end

          context "with charge fees" do
            let(:billable_metric) { create(:billable_metric, organization:) }
            let(:charge) do
              create(
                :standard_charge,
                plan:,
                billable_metric:,
                properties: {amount: "10"}
              )
            end
            let(:event) do
              create(
                :event,
                organization:,
                customer:,
                subscription:,
                billable_metric:,
                properties: {value: 5},
                timestamp: timestamp
              )
            end

            before do
              charge
              event
            end

            it "creates preview invoice for full month" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.fees.length).to eq(2)
                expect(result.invoice.fees_amount_cents).to eq(1100)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(1100)
                expect(result.invoice.taxes_amount_cents).to eq(550)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(1650)
                expect(result.invoice.total_amount_cents).to eq(1650)
              end
            end
          end
        end

        context "with multiple persisted subscriptions" do
          let(:customer) { create(:customer, organization:, billing_entity:) }
          let(:plan2) { create(:plan, organization:, interval: "monthly") }
          let(:subscription1) do
            create(
              :subscription,
              customer:,
              plan:,
              billing_time:,
              subscription_at: timestamp,
              started_at: timestamp,
              created_at: timestamp
            )
          end
          let(:subscription2) do
            create(
              :subscription,
              customer:,
              plan: plan2,
              billing_time:,
              subscription_at: timestamp,
              started_at: timestamp,
              created_at: timestamp
            )
          end
          let(:subscriptions) { [subscription1, subscription2] }

          before { organization.update!(premium_integrations: ["preview"]) }

          it "creates preview invoice for full month" do
            travel_to(timestamp) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.subscriptions.size).to eq(2)
              expect(result.invoice.fees.length).to eq(2)
              expect(result.invoice.fees_amount_cents).to eq(200)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(200)
              expect(result.invoice.taxes_amount_cents).to eq(100)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(300)
              expect(result.invoice.total_amount_cents).to eq(300)
            end
          end
        end
      end
    end
  end
end
