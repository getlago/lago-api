# frozen_string_literal: true

require "rails_helper"

RSpec.describe DailyUsages::FillFromInvoiceService, type: :service do
  subject(:fill_service) { described_class.new(invoice:, subscriptions:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription) { create(:subscription, customer:) }
  let(:subscriptions) { [subscription] }

  let(:timestamp) { Time.zone.parse("2025-01-01T01:00:00") }

  let(:invoice) do
    create(
      :invoice,
      organization:,
      issuing_date: Time.zone.at(timestamp).to_date,
      customer:
    )
  end

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      subscription:,
      invoice:,
      timestamp:,
      from_datetime: Time.zone.parse("2024-12-01T00:00:00"),
      to_datetime: Time.zone.parse("2024-12-31T23:59:59"),
      charges_from_datetime: Time.zone.parse("2024-12-01T00:00:00"),
      charges_to_datetime: Time.zone.parse("2024-12-31T23:59:59")
    )
  end

  before { invoice_subscription }

  describe "#call" do
    context "when there is no usage" do
      it "does not create a daily usage" do
        travel_to(timestamp) do
          expect { fill_service.call }.not_to change(DailyUsage, :count)
        end
      end
    end

    context "when there is usage" do
      before do
        charge = create(:standard_charge, plan: subscription.plan)
        create(:charge_fee, invoice:, charge:, units: 12, amount_cents: 1200, subscription:)
      end

      it "creates daily usages for the subscriptions" do
        travel_to(timestamp) do
          expect { fill_service.call }.to change(DailyUsage, :count).by(1)

          daily_usage = subscription.daily_usages.order(:created_at).last
          expect(daily_usage).to have_attributes(
            organization:,
            customer:,
            subscription:,
            external_subscription_id: subscription.external_id,
            usage: Hash,
            from_datetime: invoice_subscription.from_datetime,
            to_datetime: invoice_subscription.to_datetime,
            refreshed_at: invoice_subscription.timestamp,
            usage_diff: Hash,
            usage_date: invoice_subscription.charges_to_datetime.to_date
          )
        end
      end

      context "when invoice contains fees with 0 units" do
        it "does not include those fees in the usage" do
          charge = create(:standard_charge, plan: subscription.plan)
          create(:charge_fee, invoice:, charge:, units: 0, amount_cents: 0, subscription:)

          travel_to(timestamp) do
            expect { fill_service.call }.to change(DailyUsage, :count).by(1)
            daily_usage = subscription.daily_usages.order(:created_at).last
            expect(daily_usage.usage["charges_usage"].count).to eq(1)
          end
        end
      end

      context "when the daily usage already exists" do
        before do
          create(
            :daily_usage,
            organization:,
            customer:,
            subscription:,
            external_subscription_id: subscription.external_id,
            from_datetime: invoice_subscription.from_datetime,
            to_datetime: invoice_subscription.to_datetime,
            refreshed_at: invoice_subscription.timestamp,
            usage_date: invoice_subscription.charges_to_datetime.to_date
          )
        end

        it "does not create a new daily usage" do
          expect { fill_service.call }.not_to change(DailyUsage, :count)
        end
      end

      context "when multiples subscriptions are passed to the service" do
        let(:subscription2) { create(:subscription, customer:) }
        let(:subscriptions) { [subscription, subscription2] }

        let(:invoice_subscription2) do
          create(
            :invoice_subscription,
            subscription: subscription2,
            invoice:,
            timestamp:,
            from_datetime: Time.zone.parse("2024-12-01T00:00:00"),
            to_datetime: Time.zone.parse("2024-12-31T23:59:59"),
            charges_from_datetime: Time.zone.parse("2024-12-01T00:00:00"),
            charges_to_datetime: Time.zone.parse("2024-12-31T23:59:59")
          )
        end

        before { invoice_subscription2 }

        it "creates daily usages for all the subscriptions" do
          expect { fill_service.call }.to change(DailyUsage, :count).by(2)
        end

        context "when only one subscription has to be updated" do
          let(:subscriptions) { [subscription] }

          it "creates daily usages for the subscriptions" do
            expect { fill_service.call }.to change(DailyUsage, :count).by(1)

            daily_usage = subscription.daily_usages.order(:created_at).last
            expect(daily_usage).to have_attributes(
              organization:,
              customer:,
              subscription:,
              external_subscription_id: subscription.external_id,
              usage: Hash,
              from_datetime: invoice_subscription.from_datetime,
              to_datetime: invoice_subscription.to_datetime,
              refreshed_at: invoice_subscription.timestamp,
              usage_diff: Hash,
              usage_date: invoice_subscription.charges_to_datetime.to_date
            )
          end
        end
      end
    end
  end
end
