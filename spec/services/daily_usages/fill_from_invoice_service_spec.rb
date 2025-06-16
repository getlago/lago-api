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
      charges_from_datetime: Time.zone.parse("2024-12-01T00:00:00.123456"),
      charges_to_datetime: Time.zone.parse("2024-12-31T23:59:59.123456")
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

  describe "#existing_daily_usage" do
    context "when no daily usage exists" do
      it "returns nil" do
        result = fill_service.send(:existing_daily_usage, invoice_subscription)
        expect(result).to be_nil
      end
    end

    context "when no matching daily usage exists" do
      before do
        create(
          :daily_usage,
          organization: invoice.organization,
          customer: invoice.customer,
          subscription: subscription,
          external_subscription_id: subscription.external_id,
          from_datetime: invoice_subscription.charges_from_datetime,
          to_datetime: invoice_subscription.charges_to_datetime,
          refreshed_at: invoice_subscription.timestamp,
          usage_date: invoice_subscription.charges_to_datetime.to_date
        )
      end

      it "returns nil" do
        result = fill_service.send(:existing_daily_usage, invoice_subscription)
        expect(result).to be_nil
      end
    end

    context "when a matching daily usage exists" do
      let!(:existing_usage) do
        create(
          :daily_usage,
          organization: invoice.organization,
          customer: invoice.customer,
          subscription: subscription,
          external_subscription_id: subscription.external_id,
          from_datetime: invoice_subscription.charges_from_datetime.change(usec: 0),
          to_datetime: invoice_subscription.charges_to_datetime.change(usec: 0),
          refreshed_at: invoice_subscription.timestamp,
          usage_date: invoice_subscription.charges_to_datetime.to_date
        )
      end

      it "returns the existing daily usage" do
        result = fill_service.send(:existing_daily_usage, invoice_subscription)
        expect(result).to eq(existing_usage)
      end
    end
  end

  describe "#invoice_usage" do
    subject(:usage) { fill_service.send(:invoice_usage, subscription, invoice_subscription) }

    let(:charge) { create(:standard_charge, plan: subscription.plan) }

    it "returns an OpenStruct with correct datetime attributes" do
      expect(usage.from_datetime).to eq(invoice_subscription.charges_from_datetime.change(usec: 0))
      expect(usage.to_datetime).to eq(invoice_subscription.charges_to_datetime.change(usec: 0))
    end

    it "returns the issuing_date as an ISO8601 string" do
      expect(usage.issuing_date).to eq(invoice.issuing_date.iso8601)
    end

    context "when invoice contains fees that should be excluded" do
      let(:charge_fee) do
        create(
          :charge_fee,
          invoice:,
          charge:,
          subscription:,
          units: 10,
          amount_cents: 1000,
          taxes_amount_cents: 100
        )
      end

      before do
        charge_fee
        create(:fee, invoice:, subscription:)
      end

      it "includes only fees with positive units belonging to the subscription" do
        result = fill_service.send(:invoice_usage, subscription, invoice_subscription)

        expect(result.fees.count).to eq(1)
        expect(result.fees.first).to eq(charge_fee)
        expect(result.total_amount_cents).to eq(1100)
      end
    end
  end
end
