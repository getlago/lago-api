# frozen_string_literal: true

require "rails_helper"

RSpec.describe InvoiceSubscription, type: :model do
  subject(:invoice_subscription) do
    create(
      :invoice_subscription,
      from_datetime:,
      to_datetime:,
      charges_from_datetime:,
      charges_to_datetime:
    )
  end

  let(:invoice) { invoice_subscription.invoice }
  let(:subscription) { invoice_subscription.subscription }

  let(:from_datetime) { "2022-01-01 00:00:00" }
  let(:to_datetime) { "2022-01-31 23:59:59" }
  let(:charges_from_datetime) { "2022-01-01 00:00:00" }
  let(:charges_to_datetime) { "2022-01-31 23:59:59" }

  it { is_expected.to belong_to(:organization) }

  describe ".matching?" do
    subject(:matching_call) { described_class.matching?(subscription, boundaries, recurring:) }

    let(:recurring) { true }
    let(:subscription) { create(:subscription, plan:) }

    let(:boundaries) do
      OpenStruct.new(
        from_datetime:,
        to_datetime:,
        charges_from_datetime:,
        charges_to_datetime:
      )
    end

    context "when plan is yearly and bills charges monthly" do
      let(:plan) { create(:plan, :yearly, bill_charges_monthly: true) }

      context "when an exact matching recurring invoice_subscription exists" do
        before do
          create(
            :invoice_subscription,
            subscription:,
            from_datetime:,
            to_datetime:,
            charges_from_datetime:,
            charges_to_datetime:,
            recurring: true
          )
        end

        it "returns true" do
          expect(subject).to be true
        end
      end

      context "when only from/to match but charge boundaries differ" do
        before do
          create(
            :invoice_subscription,
            subscription:,
            from_datetime:,
            to_datetime:,
            charges_from_datetime: DateTime.parse(charges_from_datetime) - 2.days,
            charges_to_datetime: DateTime.parse(charges_to_datetime) - 2.days,
            recurring: true
          )
        end

        it "returns false because charge boundaries must match" do
          expect(subject).to be false
        end
      end

      context "when matching invoice_subscription is non recurring and recurring flag is true" do
        let(:recurring) { true }

        before do
          create(
            :invoice_subscription,
            subscription:,
            from_datetime:,
            to_datetime:,
            charges_from_datetime:,
            charges_to_datetime:,
            recurring: false
          )
        end

        it "returns false (filtered out by recurring scope)" do
          expect(subject).to be false
        end
      end

      context "when matching invoice_subscription is non recurring and recurring flag is false" do
        let(:recurring) { false }

        before do
          create(
            :invoice_subscription,
            subscription:,
            from_datetime:,
            to_datetime:,
            charges_from_datetime:,
            charges_to_datetime:,
            recurring: false
          )
        end

        it "returns true (recurring scope not applied)" do
          expect(subject).to be true
        end
      end
    end

    context "when plan is semiannual and bills charges monthly" do
      let(:plan) { create(:plan, :semiannual, bill_charges_monthly: true) }

      context "when only from/to match but charge boundaries differ" do
        before do
          create(
            :invoice_subscription,
            subscription:,
            from_datetime:,
            to_datetime:,
            charges_from_datetime: DateTime.parse(charges_from_datetime) - 3.days,
            charges_to_datetime: DateTime.parse(charges_to_datetime) - 3.days,
            recurring: true
          )
        end

        it "returns false (charge boundaries must match for semiannual plan)" do
          expect(subject).to be false
        end
      end
    end

    context "when plan is monthly and bills charges monthly" do
      let(:plan) { create(:plan, :monthly, bill_charges_monthly: true) }

      context "when only from/to match and charge boundaries differ" do
        before do
          create(
            :invoice_subscription,
            subscription:,
            from_datetime:,
            to_datetime:,
            charges_from_datetime: DateTime.parse(charges_from_datetime) - 5.days,
            charges_to_datetime: DateTime.parse(charges_to_datetime) - 5.days,
            recurring: true
          )
        end

        it "returns true (charge boundaries ignored for monthly plan)" do
          expect(subject).to be true
        end
      end
    end

    context "when plan does not bill charges monthly (yearly plan)" do
      let(:plan) { create(:plan, :yearly, bill_charges_monthly: false) }

      context "when only from/to match and charge boundaries differ" do
        before do
          create(
            :invoice_subscription,
            subscription:,
            from_datetime:,
            to_datetime:,
            charges_from_datetime: DateTime.parse(charges_from_datetime) - 1.day,
            charges_to_datetime: DateTime.parse(charges_to_datetime) - 1.day,
            recurring: true
          )
        end

        it "returns true (charges boundaries not applied if plan not billing charges monthly)" do
          expect(subject).to be true
        end
      end
    end
  end

  describe "#fees" do
    it "returns corresponding fees" do
      first_fee = create(:fee, subscription_id: subscription.id, invoice_id: invoice.id)
      create(:fee, subscription_id: subscription.id)
      create(:fee, invoice_id: invoice.id)

      expect(invoice_subscription.fees).to eq([first_fee])
    end
  end

  describe "#charge_amount_cents" do
    it "returns the sum of the related charge fees" do
      charge = create(:standard_charge)
      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge:,
        amount_cents: 100
      )

      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge:,
        amount_cents: 200
      )

      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        amount_cents: 400
      )

      expect(invoice_subscription.charge_amount_cents).to eq(300)
    end
  end

  describe "#subscription_amount_cents" do
    it "returns the amount of the subscription fees" do
      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        amount_cents: 50
      )

      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge: create(:standard_charge),
        amount_cents: 200
      )

      expect(invoice_subscription.subscription_amount_cents).to eq(50)
    end
  end

  describe "#total_amount_cents" do
    it "returns the sum of the related fees" do
      charge = create(:standard_charge)
      create(
        :fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        amount_cents: 50
      )

      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge:,
        amount_cents: 200
      )

      create(
        :charge_fee,
        subscription_id: subscription.id,
        invoice_id: invoice.id,
        charge:,
        amount_cents: 100
      )

      expect(invoice_subscription.total_amount_cents).to eq(350)
    end
  end

  describe "#total_amount_currency" do
    it "returns the currency of the total amount" do
      expect(invoice_subscription.total_amount_currency).to eq(subscription.plan.amount_currency)
    end
  end

  describe "#charge_amount_currency" do
    it "returns the currency of the charge amount" do
      expect(invoice_subscription.charge_amount_currency).to eq(subscription.plan.amount_currency)
    end
  end

  describe "#subscription_amount_currency" do
    it "returns the currency of the subscription amount" do
      expect(invoice_subscription.subscription_amount_currency).to eq(subscription.plan.amount_currency)
    end
  end

  describe "#previous_invoice_subscription" do
    subject(:previous_invoice_subscription_call) { invoice_subscription.previous_invoice_subscription }

    context "when it has previous invoice subscription" do
      let(:previous_invoice_subscription) do
        create(
          :invoice_subscription,
          subscription: invoice_subscription.subscription,
          from_datetime: invoice_subscription.from_datetime - 1.year,
          to_datetime: invoice_subscription.to_datetime - 1.year,
          charges_from_datetime: invoice_subscription.charges_from_datetime - 1.year,
          charges_to_datetime: invoice_subscription.charges_to_datetime - 1.year
        )
      end

      before do
        previous_invoice_subscription

        create(
          :fee,
          subscription: previous_invoice_subscription.subscription,
          invoice: previous_invoice_subscription.invoice,
          amount_cents: 857 # prorated
        )
      end

      it "returns previous invoice subscription" do
        expect(previous_invoice_subscription_call).to eq(previous_invoice_subscription)
      end
    end

    context "when there is a previous invoice subscription for different subscription" do
      let(:previous_invoice_subscription) do
        create(
          :invoice_subscription,
          from_datetime: invoice_subscription.from_datetime - 1.year,
          to_datetime: invoice_subscription.to_datetime - 1.year,
          charges_from_datetime: invoice_subscription.charges_from_datetime - 1.year,
          charges_to_datetime: invoice_subscription.charges_to_datetime - 1.year
        )
      end

      before do
        previous_invoice_subscription

        create(
          :invoice_subscription,
          from_datetime: invoice_subscription.from_datetime - 2.years,
          to_datetime: invoice_subscription.to_datetime - 2.years,
          charges_from_datetime: invoice_subscription.charges_from_datetime - 2.years,
          charges_to_datetime: invoice_subscription.charges_to_datetime - 2.years
        )
      end

      it "returns nil" do
        expect(previous_invoice_subscription_call).to be(nil)
      end
    end

    context "when it has no previous invoice subscription" do
      before do
        create(
          :invoice_subscription,
          from_datetime: invoice_subscription.from_datetime + 1.year,
          to_datetime: invoice_subscription.to_datetime + 1.year,
          charges_from_datetime: invoice_subscription.charges_from_datetime + 1.year,
          charges_to_datetime: invoice_subscription.charges_to_datetime + 1.year
        )
      end

      it "returns nil" do
        expect(previous_invoice_subscription_call).to be(nil)
      end
    end
  end
end
