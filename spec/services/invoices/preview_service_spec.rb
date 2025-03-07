# frozen_string_literal: true

require "rails_helper"

RSpec.describe Invoices::PreviewService, type: :service, cache: :memory do
  subject(:preview_service) { described_class.new(customer:, subscriptions:) }

  describe "#call" do
    let(:organization) { create(:organization) }
    let(:tax) { create(:tax, rate: 50.0, organization:) }
    let(:customer) { build(:customer, organization:) }
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
        it "returns an error" do
          result = described_class.new(customer: nil, subscriptions: [subscription]).call

          expect(result).not_to be_success
          expect(result.error.error_code).to eq("customer_not_found")
        end
      end

      context "when subscriptions are missing" do
        let(:subscriptions) { [] }

        it "returns an error" do
          result = preview_service.call

          expect(result).not_to be_success
          expect(result.error.error_code).to eq("subscription_not_found")
        end
      end

      context "when currencies do not match" do
        let(:customer) { build(:customer, organization:, currency: "USD") }

        it "returns an error" do
          result = preview_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:base]).to include("customer_currency_does_not_match")
        end
      end

      context "when billing periods do not match" do
        let(:customer) { create(:customer, organization:) }
        let(:plan1) { create(:plan, organization:, interval: "monthly") }
        let(:plan2) { create(:plan, organization:, interval: "monthly") }
        let(:subscriptions) { [subscription1, subscription2] }
        let(:subscription1) do
          create(:subscription, plan: plan1, customer:, subscription_at: Time.current.beginning_of_month - 10.days, billing_time: "anniversary")
        end
        let(:subscription2) do
          create(:subscription, plan: plan2, customer:, subscription_at: Time.current.beginning_of_month - 9.days, billing_time: "anniversary")
        end

        before { organization.update!(premium_integrations: ["preview"]) }

        it "returns an error" do
          result = preview_service.call

          expect(result).not_to be_success
          expect(result.error.messages[:base]).to include("billing_periods_does_not_match")
        end
      end

      context "with calendar billing" do
        it "creates preview invoice for 2 days" do
          # Two days should be billed, Mar 30 and Mar 31

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
            expect(result.invoice.total_amount_cents).to eq(9)
          end
        end

        context "with one persisted subscription" do
          let(:customer) { create(:customer, organization:) }
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
            let(:billable_metric) do
              create(:billable_metric, aggregation_type: "count_agg")
            end
            let(:charge) do
              create(
                :standard_charge,
                plan:,
                billable_metric:,
                properties: {amount: "12.66"}
              )
            end
            let(:events) do
              create_list(
                :event,
                2,
                organization:,
                subscription:,
                customer:,
                code: billable_metric.code,
                timestamp: timestamp + 10.hours
              )
            end

            before do
              events if subscription
              charge
              Rails.cache.clear
            end

            it "creates preview invoice for 2 days" do
              # Two days should be billed, Mar 30 and Mar 31

              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
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

            it "uses the Rails cache" do
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
            before { organization.update!(premium_integrations: ["netsuite"]) }

            it "returns an error" do
              result = preview_service.call

              aggregate_failures do
                expect(result).not_to be_success
                expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
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
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.invoice_type).to eq("subscription")
              expect(result.invoice.issuing_date.to_s).to eq("2024-03-31")
              expect(result.invoice.fees_amount_cents).to eq(3)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(3)
              expect(result.invoice.taxes_amount_cents).to eq(2)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(5)
              expect(result.invoice.total_amount_cents).to eq(5)
            end
          end
        end

        context "with in advance billing with persisted subscription" do
          let(:customer) { create(:customer, organization:) }
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

          context "when preview premium integration does not exist" do
            before { organization.update!(premium_integrations: ["netsuite"]) }

            it "returns an error" do
              result = preview_service.call

              aggregate_failures do
                expect(result).not_to be_success
                expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
              end
            end
          end
        end

        context "with applied coupons" do
          let(:applied_coupon) do
            build(
              :applied_coupon,
              customer: subscription.customer,
              amount_cents: 2,
              amount_currency: plan.amount_currency
            )
          end

          it "creates preview invoice for 2 days with applied coupons" do
            travel_to(timestamp) do
              result = described_class.new(customer:, subscriptions: [subscription], applied_coupons: [applied_coupon]).call

              expect(result).to be_success
              expect(result.invoice.subscriptions.first).to eq(subscription)
              expect(result.invoice.fees.length).to eq(1)
              expect(result.invoice.invoice_type).to eq("subscription")
              expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
              expect(result.invoice.fees_amount_cents).to eq(6)
              expect(result.invoice.coupons_amount_cents).to eq(2)
              expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(4)
              expect(result.invoice.taxes_amount_cents).to eq(2)
              expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(6)
              expect(result.invoice.total_amount_cents).to eq(6)
              expect(result.invoice.credits.length).to eq(1)
            end
          end
        end

        context "with credit note credits" do
          let(:credit_note) do
            create(
              :credit_note,
              customer:,
              total_amount_cents: 2,
              total_amount_currency: plan.amount_currency,
              balance_amount_cents: 2,
              balance_amount_currency: plan.amount_currency,
              credit_amount_cents: 2,
              credit_amount_currency: plan.amount_currency
            )
          end

          before { credit_note }

          it "creates preview invoice for 2 days with credits included" do
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
              expect(result.invoice.credit_notes_amount_cents).to eq(2)
              expect(result.invoice.total_amount_cents).to eq(7)
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
            let(:customer) { create(:customer, organization:) }
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
          let(:integration) { create(:anrok_integration, organization:) }
          let(:integration_customer) { build(:anrok_customer, integration:, customer:) }
          let(:endpoint) { "https://api.nango.dev/v1/anrok/draft_invoices" }
          let(:integration_collection_mapping) do
            create(
              :netsuite_collection_mapping,
              integration:,
              mapping_type: :fallback_item,
              settings: {external_id: "1", external_account_code: "11", external_name: ""}
            )
          end

          before do
            integration_collection_mapping
            customer.integration_customers = [integration_customer]
          end

          context "when there is no error" do
            before do
              stub_request(:post, endpoint).to_return do |request|
                response = JSON.parse(File.read(
                  Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/success_response.json")
                ))

                # setting item_id based on the test example
                key = JSON.parse(request.body).first["fees"].last["item_key"]
                response["succeededInvoices"].first["fees"].last["item_key"] = key

                {body: response.to_json}
              end
            end

            it "creates preview invoice for 2 days" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.subscriptions.first).to eq(subscription)
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.invoice_type).to eq("subscription")
                expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
                expect(result.invoice.fees_amount_cents).to eq(6)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(6)
                expect(result.invoice.taxes_amount_cents).to eq(1) # 6 x 0.1
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(7)
                expect(result.invoice.total_amount_cents).to eq(7)
              end
            end
          end

          context "when there is error received from the provider" do
            before do
              stub_request(:post, endpoint).to_return do |request|
                response = File.read(
                  Rails.root.join("spec/fixtures/integration_aggregator/taxes/invoices/failure_response.json")
                )
                {body: response}
              end
            end

            it "uses zero taxes" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.subscriptions.first).to eq(subscription)
                expect(result.invoice.fees.length).to eq(1)
                expect(result.invoice.invoice_type).to eq("subscription")
                expect(result.invoice.issuing_date.to_s).to eq("2024-04-01")
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

        context "with one persisted subscriptions" do
          let(:customer) { create(:customer, organization:) }
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
            let(:billable_metric) do
              create(:billable_metric, aggregation_type: "count_agg")
            end
            let(:charge) do
              create(
                :standard_charge,
                plan:,
                billable_metric:,
                properties: {amount: "12.66"}
              )
            end
            let(:events) do
              create_list(
                :event,
                2,
                organization:,
                subscription:,
                customer:,
                code: billable_metric.code,
                timestamp: timestamp + 10.hours
              )
            end

            before do
              events if subscription
              charge
              Rails.cache.clear
            end

            it "creates preview invoice for full month" do
              travel_to(timestamp) do
                result = preview_service.call

                expect(result).to be_success
                expect(result.invoice.subscriptions.first).to eq(subscription)
                expect(result.invoice.fees.length).to eq(2)
                expect(result.invoice.invoice_type).to eq("subscription")
                expect(result.invoice.issuing_date.to_s).to eq("2024-04-30")
                expect(result.invoice.fees_amount_cents).to eq(2632)
                expect(result.invoice.sub_total_excluding_taxes_amount_cents).to eq(2632)
                expect(result.invoice.taxes_amount_cents).to eq(1316)
                expect(result.invoice.sub_total_including_taxes_amount_cents).to eq(3948)
                expect(result.invoice.total_amount_cents).to eq(3948)
              end
            end
          end
        end

        context "with multiple persisted subscriptions" do
          let(:customer) { create(:customer, organization:) }
          let(:plan1) { create(:plan, organization:, interval: "monthly") }
          let(:plan2) { create(:plan, organization:, interval: "monthly") }
          let(:subscriptions) { [subscription1, subscription2] }
          let(:subscription1) do
            create(
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

          before { organization.update!(premium_integrations: ["preview"]) }

          it "creates preview invoice for full month" do
            travel_to(timestamp + 5.days) do
              result = preview_service.call

              expect(result).to be_success
              expect(result.invoice.subscriptions.map { |s| s.id }).to match_array([subscription1.id, subscription2.id])
              expect(result.invoice.fees.length).to eq(2)
              expect(result.invoice.invoice_type).to eq("subscription")
              expect(result.invoice.issuing_date.to_s).to eq("2024-04-30")
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
