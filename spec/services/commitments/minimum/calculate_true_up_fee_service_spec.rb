# frozen_string_literal: true

require "rails_helper"

RSpec.describe Commitments::Minimum::CalculateTrueUpFeeService do
  subject(:service) { described_class.new_instance(invoice_subscription:) }

  let(:invoice_subscription) do
    create(
      :invoice_subscription,
      subscription:,
      from_datetime:,
      to_datetime:,
      charges_from_datetime:,
      charges_to_datetime:,
      fixed_charges_from_datetime:,
      fixed_charges_to_datetime:,
      timestamp:
    )
  end

  let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
  let(:to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
  let(:charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
  let(:charges_to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
  let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
  let(:fixed_charges_to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
  let(:timestamp) { DateTime.parse("2025-01-01T10:00:00") }
  let(:subscription) { create(:subscription, customer:, plan:, billing_time:, subscription_at:) }
  let(:customer) { create(:customer, organization:) }
  let(:subscription_at) { DateTime.parse("2024-01-01T00:00:00") }
  let(:organization) { create(:organization) }
  let(:plan) { create(:plan, organization:, pay_in_advance:, interval:, bill_charges_monthly:, bill_fixed_charges_monthly:) }
  let(:billing_time) { :calendar }
  let(:bill_charges_monthly) { false }
  let(:bill_fixed_charges_monthly) { false }
  let(:pay_in_advance) { false }
  let(:interval) { :yearly }
  let(:fixed_charge) { create(:fixed_charge, plan:, pay_in_advance: false) }
  let(:fixed_charge_pay_in_advance) { create(:fixed_charge, :pay_in_advance, plan:) }

  describe "#call" do
    subject(:service_call) { service.call }

    context "when plan is paid in arrears" do
      let(:pay_in_advance) { false }

      context "when plan has no minimum commitment" do
        it "returns result with zero amount cents" do
          expect(service_call.amount_cents).to eq(0)
        end
      end

      context "when plan has minimum commitment" do
        let(:commitment) { create(:commitment, plan:, amount_cents: commitment_amount_cents) }
        let(:commitment_amount_cents) { 200 }

        before { commitment }

        context "when there are no fees" do
          it "returns result with amount cents" do
            expect(service_call.amount_cents).to eq(commitment_amount_cents)
          end
        end

        context "when there are subscription fees" do
          let(:charge) { create(:standard_charge) }

          before do
            create(
              :fee,
              subscription: invoice_subscription.subscription,
              invoice: invoice_subscription.invoice,
              amount_cents: 200
            )

            create(
              :charge_fee,
              subscription: invoice_subscription.subscription,
              invoice: invoice_subscription.invoice,
              charge:,
              amount_cents: 300,
              properties: {
                charges_from_datetime:,
                charges_to_datetime:
              }
            )

            create(
              :fixed_charge_fee,
              subscription: invoice_subscription.subscription,
              invoice: invoice_subscription.invoice,
              fixed_charge:,
              amount_cents: 150,
              properties: {
                fixed_charges_from_datetime:,
                fixed_charges_to_datetime:
              }
            )
          end

          context "when subscription is anniversary" do
            let(:billing_time) { :anniversary }

            context "when plan has yearly interval" do
              let(:interval) { :yearly }
              let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2025-01-01T10:00:00") }

              context "when plan is billed yearly" do
                context "when fees total amount is greater or equal than the commitment amount" do
                  it "returns result with zero amount cents" do
                    expect(service_call.amount_cents).to eq(0)
                  end
                end

                context "when fees total amount is smaller than the commitment amount" do
                  let(:commitment_amount_cents) { 10_000 }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 1.year,
                          charges_to_datetime: charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 1.year,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end
                end
              end

              context "when charges are billed monthly" do
                let(:bill_charges_monthly) { true }
                let(:commitment_amount_cents) { 10_000 }

                let(:invoice_subscription_previous) do
                  create(
                    :invoice_subscription,
                    subscription:,
                    from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    fixed_charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    fixed_charges_to_datetime: DateTime.parse("2024-12-31T23:59:59.999"),
                    timestamp: DateTime.parse("2024-02-01T10:00:00")
                  )
                end

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: invoice_subscription_previous.invoice,
                      subscription: invoice_subscription_previous.subscription,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: charges_from_datetime + 1.year,
                        charges_to_datetime: charges_to_datetime + 1.year
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: invoice_subscription_previous.invoice,
                      subscription: invoice_subscription_previous.subscription,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: invoice_subscription_previous.invoice,
                      subscription: invoice_subscription_previous.subscription,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: invoice_subscription_previous.invoice,
                      subscription: invoice_subscription_previous.subscription,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: fixed_charges_from_datetime + 1.year,
                        fixed_charges_to_datetime: fixed_charges_to_datetime + 1.year
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: invoice_subscription_previous.invoice,
                      subscription: invoice_subscription_previous.subscription,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: invoice_subscription_previous.invoice,
                      subscription: invoice_subscription_previous.subscription,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end

              context "when fixed charges are billed monthly" do
                let(:bill_fixed_charges_monthly) { true }
                let(:commitment_amount_cents) { 10_000 }

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: charges_from_datetime + 1.year,
                        charges_to_datetime: charges_to_datetime + 1.year
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: fixed_charges_from_datetime + 1.year,
                        fixed_charges_to_datetime: fixed_charges_to_datetime + 1.year
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end
            end

            context "when plan has semiannual interval" do
              let(:interval) { :semiannual }
              let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-06-30T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-06-30T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-06-30T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2024-07-01T10:00:00") }

              context "when fees total amount is greater or equal than the commitment amount" do
                it "returns result with zero amount cents" do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context "when fees total amount is smaller than the commitment amount" do
                let(:commitment_amount_cents) { 10_000 }

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: charges_from_datetime + 6.months,
                        charges_to_datetime: charges_to_datetime + 6.months
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: fixed_charges_from_datetime + 6.months,
                        fixed_charges_to_datetime: fixed_charges_to_datetime + 6.months
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end
            end

            context "when charges are billed monthly" do
              let(:bill_charges_monthly) { true }
              let(:commitment_amount_cents) { 10_000 }

              let(:invoice_subscription_previous) do
                create(
                  :invoice_subscription,
                  subscription:,
                  from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                  to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                  charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                  charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                  fixed_charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                  fixed_charges_to_datetime: DateTime.parse("2024-06-30T23:59:59.999"),
                  timestamp: DateTime.parse("2024-07-01T10:00:00")
                )
              end

              context "with an in-advance charge for the next period" do
                before do
                  create(
                    :charge_fee,
                    invoice: invoice_subscription_previous.invoice,
                    subscription: invoice_subscription_previous.subscription,
                    pay_in_advance: true,
                    charge: create(:standard_charge, :pay_in_advance),
                    amount_cents: 500,
                    properties: {
                      charges_from_datetime: charges_from_datetime + 6.months,
                      charges_to_datetime: charges_to_datetime + 6.months
                    }
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(9_350)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end

              context "with an in-advance charge for current period" do
                before do
                  create(
                    :charge_fee,
                    invoice: invoice_subscription_previous.invoice,
                    subscription: invoice_subscription_previous.subscription,
                    pay_in_advance: true,
                    charge: create(:standard_charge, :pay_in_advance),
                    amount_cents: 500,
                    properties: {
                      charges_from_datetime:,
                      charges_to_datetime:
                    }
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(8_850)
                  expect(service_call.amount_cents).to eq(9_000)
                end
              end

              context "with an in-advance charge from another period" do
                before do
                  create(
                    :charge_fee,
                    invoice: invoice_subscription_previous.invoice,
                    subscription: invoice_subscription_previous.subscription,
                    pay_in_advance: true,
                    charge: create(:standard_charge, :pay_in_advance),
                    amount_cents: 500
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(9_350)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end

              context "with an in-advance fixed charge for the next period" do
                before do
                  create(
                    :fixed_charge_fee,
                    invoice: invoice_subscription_previous.invoice,
                    subscription: invoice_subscription_previous.subscription,
                    pay_in_advance: true,
                    fixed_charge: fixed_charge_pay_in_advance,
                    amount_cents: 500,
                    properties: {
                      fixed_charges_from_datetime: fixed_charges_from_datetime + 6.months,
                      fixed_charges_to_datetime: fixed_charges_to_datetime + 6.months
                    }
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(9_350)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end

              context "with an in-advance fixed charge for current period" do
                before do
                  create(
                    :fixed_charge_fee,
                    invoice: invoice_subscription_previous.invoice,
                    subscription: invoice_subscription_previous.subscription,
                    pay_in_advance: true,
                    fixed_charge: fixed_charge_pay_in_advance,
                    amount_cents: 500,
                    properties: {
                      fixed_charges_from_datetime:,
                      fixed_charges_to_datetime:
                    }
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(8_850)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end

              context "with an in-advance fixed charge from another period" do
                before do
                  create(
                    :fixed_charge_fee,
                    invoice: invoice_subscription_previous.invoice,
                    subscription: invoice_subscription_previous.subscription,
                    pay_in_advance: true,
                    fixed_charge: fixed_charge_pay_in_advance,
                    amount_cents: 500
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(9_350)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end
            end

            context "when fixed charges are billed monthly" do
              let(:bill_fixed_charges_monthly) { true }
              let(:commitment_amount_cents) { 10_000 }

              context "with an in-advance charge for the next period" do
                before do
                  create(
                    :charge_fee,
                    invoice: nil,
                    subscription:,
                    pay_in_advance: true,
                    charge: create(:standard_charge, :pay_in_advance),
                    amount_cents: 500,
                    properties: {
                      charges_from_datetime: charges_from_datetime + 6.months,
                      charges_to_datetime: charges_to_datetime + 6.months
                    }
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(9_350)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end

              context "with an in-advance charge for current period" do
                before do
                  create(
                    :charge_fee,
                    invoice: nil,
                    subscription:,
                    pay_in_advance: true,
                    charge: create(:standard_charge, :pay_in_advance),
                    amount_cents: 500,
                    properties: {
                      charges_from_datetime:,
                      charges_to_datetime:
                    }
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(8_850)
                  expect(service_call.amount_cents).to eq(9_000)
                end
              end

              context "with an in-advance charge from another period" do
                before do
                  create(
                    :charge_fee,
                    invoice: nil,
                    subscription:,
                    pay_in_advance: true,
                    charge: create(:standard_charge, :pay_in_advance),
                    amount_cents: 500
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(9_350)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end

              context "with an in-advance fixed charge for the next period" do
                before do
                  create(
                    :fixed_charge_fee,
                    invoice: nil,
                    subscription:,
                    pay_in_advance: true,
                    fixed_charge: fixed_charge_pay_in_advance,
                    amount_cents: 500,
                    properties: {
                      fixed_charges_from_datetime: fixed_charges_from_datetime + 6.months,
                      fixed_charges_to_datetime: fixed_charges_to_datetime + 6.months
                    }
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(9_350)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end

              context "with an in-advance fixed charge for current period" do
                before do
                  create(
                    :fixed_charge_fee,
                    invoice: nil,
                    subscription:,
                    pay_in_advance: true,
                    fixed_charge: fixed_charge_pay_in_advance,
                    amount_cents: 500,
                    properties: {
                      fixed_charges_from_datetime:,
                      fixed_charges_to_datetime:
                    }
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(8_850)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end

              context "with an in-advance fixed charge from another period" do
                before do
                  create(
                    :fixed_charge_fee,
                    invoice: nil,
                    subscription:,
                    pay_in_advance: true,
                    fixed_charge: fixed_charge_pay_in_advance,
                    amount_cents: 500
                  )
                end

                it "returns result with amount cents" do
                  # TODO: include fixed charge in min commitment calculations
                  # expect(service_call.amount_cents).to eq(9_350)
                  expect(service_call.amount_cents).to eq(9_500)
                end
              end
            end

            context "when plan has quarterly interval" do
              let(:interval) { :quarterly }
              let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-03-31T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-03-31T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-03-31T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2024-04-01T10:00:00") }

              context "when fees total amount is greater or equal than the commitment amount" do
                it "returns result with zero amount cents" do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context "when fees total amount is smaller than the commitment amount" do
                let(:commitment_amount_cents) { 10_000 }

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: DateTime.parse("2024-04-01T00:00:00"),
                        charges_to_datetime: DateTime.parse("2024-06-30T23:59:59.999")
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: fixed_charges_from_datetime + 3.months,
                        fixed_charges_to_datetime: fixed_charges_to_datetime + 3.months
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end
            end

            context "when plan has monthly interval" do
              let(:interval) { :monthly }
              let(:from_datetime) { DateTime.parse("2024-02-01T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-02-29T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-02-01T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-02-29T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-02-01T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-02-29T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2024-03-01T10:00:00") }

              context "when fees total amount is greater or equal than the commitment amount" do
                it "returns result with zero amount cents" do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context "when fees total amount is smaller than the commitment amount" do
                let(:commitment_amount_cents) { 10_000 }

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: DateTime.parse("2024-03-01T00:00:00"),
                        charges_to_datetime: DateTime.parse("2024-03-31T23:59:59.999")
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: fixed_charges_from_datetime + 1.month,
                        fixed_charges_to_datetime: fixed_charges_to_datetime + 1.month
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end
            end

            context "when plan has weekly interval" do
              let(:interval) { :weekly }
              let(:from_datetime) { DateTime.parse("2024-02-05T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-02-11T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-02-05T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-02-11T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-02-05T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-02-11T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2024-02-12T10:00:00") }

              context "when fees total amount is greater or equal than the commitment amount" do
                it "returns result with zero amount cents" do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context "when fees total amount is smaller than the commitment amount" do
                let(:commitment_amount_cents) { 10_000 }

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: DateTime.parse("2024-02-12T00:00:00"),
                        charges_to_datetime: DateTime.parse("2024-02-18T23:59:59.999")
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: fixed_charges_from_datetime + 1.week,
                        fixed_charges_to_datetime: fixed_charges_to_datetime + 1.week
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end
            end
          end

          context "when subscription is calendar" do
            let(:billing_time) { :calendar }

            context "when plan has yearly interval" do
              let(:interval) { :yearly }
              let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-12-31T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2025-01-01T10:00:00") }

              context "when plan is billed yearly" do
                context "when fees total amount is greater or equal than the commitment amount" do
                  it "returns result with zero amount cents" do
                    expect(service_call.amount_cents).to eq(0)
                  end
                end

                context "when fees total amount is smaller than the commitment amount" do
                  let(:commitment_amount_cents) { 10_000 }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 1.year,
                          charges_to_datetime: charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 1.year,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end
                end
              end

              context "when charges are billed monthly" do
                let(:bill_charges_monthly) { true }
                let(:commitment_amount_cents) { 10_000 }

                let(:invoice_subscription_previous) do
                  create(
                    :invoice_subscription,
                    subscription:,
                    from_datetime:,
                    to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    fixed_charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    fixed_charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    timestamp: DateTime.parse("2024-02-01T10:00:00")
                  )
                end

                before do
                  create(
                    :fee,
                    subscription: invoice_subscription_previous.subscription,
                    invoice: invoice_subscription_previous.invoice
                  )

                  create(
                    :charge_fee,
                    subscription: invoice_subscription_previous.subscription,
                    invoice: invoice_subscription_previous.invoice,
                    charge:,
                    amount_cents: 300,
                    properties: {
                      charges_from_datetime:,
                      charges_to_datetime:
                    }
                  )
                end

                context "when subscription starts at the beginning of the period" do
                  let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 1.year,
                          charges_to_datetime: charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_350)
                      expect(service_call.amount_cents).to eq(8_500)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 1.year,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_350)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end
                end

                context "when subscription does not start at the beginning of the period" do
                  let(:from_datetime) { DateTime.parse("2024-01-02T00:00:00") }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 1.year,
                          charges_to_datetime: charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_823)
                      expect(service_call.amount_cents).to eq(8_973)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_323)
                      expect(service_call.amount_cents).to eq(8_473)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_823)
                      expect(service_call.amount_cents).to eq(8_973)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 1.year,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_823)
                      expect(service_call.amount_cents).to eq(8_973)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_323)
                      expect(service_call.amount_cents).to eq(8_973)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_823)
                      expect(service_call.amount_cents).to eq(8_973)
                    end
                  end
                end
              end

              context "when fixed charges are billed monthly" do
                let(:bill_fixed_charges_monthly) { true }
                let(:commitment_amount_cents) { 10_000 }

                let(:invoice_subscription_previous) do
                  create(
                    :invoice_subscription,
                    subscription:,
                    from_datetime:,
                    to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    fixed_charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    fixed_charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    timestamp: DateTime.parse("2024-02-01T10:00:00")
                  )
                end

                before do
                  create(
                    :fee,
                    subscription: invoice_subscription_previous.subscription,
                    invoice: invoice_subscription_previous.invoice
                  )

                  create(
                    :charge_fee,
                    subscription: invoice_subscription_previous.subscription,
                    invoice: invoice_subscription_previous.invoice,
                    charge:,
                    amount_cents: 300,
                    properties: {
                      charges_from_datetime:,
                      charges_to_datetime:
                    }
                  )
                end

                context "when subscription starts at the beginning of the period" do
                  let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 1.year,
                          charges_to_datetime: charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_350)
                      expect(service_call.amount_cents).to eq(8_700)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 1.year,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_350)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end
                end

                context "when subscription does not start at the beginning of the period" do
                  let(:from_datetime) { DateTime.parse("2024-01-02T00:00:00") }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 1.year,
                          charges_to_datetime: charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_823)
                      expect(service_call.amount_cents).to eq(9_173)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_323)
                      expect(service_call.amount_cents).to eq(8_673)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_823)
                      expect(service_call.amount_cents).to eq(9_173)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 1.year,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 1.year
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_823)
                      expect(service_call.amount_cents).to eq(9_173)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_323)
                      expect(service_call.amount_cents).to eq(9_173)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_823)
                      expect(service_call.amount_cents).to eq(9_173)
                    end
                  end
                end
              end
            end

            context "when plan has semiannual interval" do
              let(:interval) { :semiannual }
              let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-06-30T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-06-30T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-06-30T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2024-07-01T10:00:00") }

              context "when plan is billed semiannually" do
                context "when fees total amount is greater or equal than the commitment amount" do
                  it "returns result with zero amount cents" do
                    expect(service_call.amount_cents).to eq(0)
                  end
                end

                context "when fees total amount is smaller than the commitment amount" do
                  let(:commitment_amount_cents) { 10_000 }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 6.months,
                          charges_to_datetime: charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 6.months,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(9_350)
                      expect(service_call.amount_cents).to eq(9_500)
                    end
                  end
                end
              end

              context "when charges are billed monthly" do
                let(:bill_charges_monthly) { true }
                let(:commitment_amount_cents) { 10_000 }

                let(:invoice_subscription_previous) do
                  create(
                    :invoice_subscription,
                    subscription:,
                    from_datetime:,
                    to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    fixed_charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    fixed_charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    timestamp: DateTime.parse("2024-02-01T10:00:00")
                  )
                end

                before do
                  create(
                    :fee,
                    subscription: invoice_subscription_previous.subscription,
                    invoice: invoice_subscription_previous.invoice
                  )

                  create(
                    :charge_fee,
                    subscription: invoice_subscription_previous.subscription,
                    invoice: invoice_subscription_previous.invoice,
                    charge:,
                    amount_cents: 300,
                    properties: {
                      charges_from_datetime:,
                      charges_to_datetime:
                    }
                  )
                end

                context "when subscription starts at the beginning of the period" do
                  let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 6.months,
                          charges_to_datetime: charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_350)
                      expect(service_call.amount_cents).to eq(8_500)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 6.months,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_350)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_000)
                    end
                  end
                end

                context "when subscription does not start at the beginning of the period" do
                  let(:from_datetime) { DateTime.parse("2024-01-02T00:00:00") }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 6.months,
                          charges_to_datetime: charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_795)
                      expect(service_call.amount_cents).to eq(8_945)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_295)
                      expect(service_call.amount_cents).to eq(8_445)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_795)
                      expect(service_call.amount_cents).to eq(8_945)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 6.months,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_795)
                      expect(service_call.amount_cents).to eq(8_945)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_295)
                      expect(service_call.amount_cents).to eq(8_945)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_795)
                      expect(service_call.amount_cents).to eq(8_945)
                    end
                  end
                end
              end

              context "when fixed charges are billed monthly" do
                let(:bill_fixed_charges_monthly) { true }
                let(:commitment_amount_cents) { 10_000 }

                let(:invoice_subscription_previous) do
                  create(
                    :invoice_subscription,
                    subscription:,
                    from_datetime:,
                    to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    fixed_charges_from_datetime: DateTime.parse("2024-01-01T00:00:00"),
                    fixed_charges_to_datetime: DateTime.parse("2024-01-31T23:59:59.999"),
                    timestamp: DateTime.parse("2024-02-01T10:00:00")
                  )
                end

                before do
                  create(
                    :fee,
                    subscription: invoice_subscription_previous.subscription,
                    invoice: invoice_subscription_previous.invoice
                  )

                  create(
                    :charge_fee,
                    subscription: invoice_subscription_previous.subscription,
                    invoice: invoice_subscription_previous.invoice,
                    charge:,
                    amount_cents: 300,
                    properties: {
                      charges_from_datetime:,
                      charges_to_datetime:
                    }
                  )
                end

                context "when subscription starts at the beginning of the period" do
                  let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 6.months,
                          charges_to_datetime: charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_350)
                      expect(service_call.amount_cents).to eq(8_700)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 6.months,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_350)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_850)
                      expect(service_call.amount_cents).to eq(9_200)
                    end
                  end
                end

                context "when subscription does not start at the beginning of the period" do
                  let(:from_datetime) { DateTime.parse("2024-01-02T00:00:00") }

                  context "with an in-advance charge for the next period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: charges_from_datetime + 6.months,
                          charges_to_datetime: charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_795)
                      expect(service_call.amount_cents).to eq(9_145)
                    end
                  end

                  context "with an in-advance charge for current period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime:,
                          charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_295)
                      expect(service_call.amount_cents).to eq(8_645)
                    end
                  end

                  context "with an in-advance charge from another period" do
                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_795)
                      expect(service_call.amount_cents).to eq(9_145)
                    end
                  end

                  context "with an in-advance fixed charge for the next period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: fixed_charges_from_datetime + 6.months,
                          fixed_charges_to_datetime: fixed_charges_to_datetime + 6.months
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_795)
                      expect(service_call.amount_cents).to eq(9_145)
                    end
                  end

                  context "with an in-advance fixed charge for current period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime:,
                          fixed_charges_to_datetime:
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_295)
                      expect(service_call.amount_cents).to eq(9_145)
                    end
                  end

                  context "with an in-advance fixed charge from another period" do
                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 500
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(8_795)
                      expect(service_call.amount_cents).to eq(9_145)
                    end
                  end
                end
              end
            end

            context "when plan has quarterly interval" do
              let(:interval) { :quarterly }
              let(:from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-03-31T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-03-31T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-01T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-03-31T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2024-04-01T10:00:00") }

              context "when fees total amount is greater or equal than the commitment amount" do
                it "returns result with zero amount cents" do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context "when fees total amount is smaller than the commitment amount" do
                let(:commitment_amount_cents) { 10_000 }

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: DateTime.parse("2024-04-01T00:00:00"),
                        charges_to_datetime: DateTime.parse("2024-06-30T23:59:59.999")
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: fixed_charges_from_datetime + 3.months,
                        fixed_charges_to_datetime: fixed_charges_to_datetime + 3.months
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end
            end

            context "when plan has monthly interval" do
              let(:interval) { :monthly }
              let(:from_datetime) { DateTime.parse("2024-02-01T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-02-29T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-02-01T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-02-29T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-02-01T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-02-29T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2024-03-01T10:00:00") }

              context "when fees total amount is greater or equal than the commitment amount" do
                it "returns result with zero amount cents" do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context "when fees total amount is smaller than the commitment amount" do
                let(:commitment_amount_cents) { 10_000 }

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: DateTime.parse("2024-03-01T00:00:00"),
                        charges_to_datetime: DateTime.parse("2024-03-31T23:59:59.999")
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: DateTime.parse("2024-03-01T00:00:00"),
                        fixed_charges_to_datetime: DateTime.parse("2024-03-31T23:59:59.999")
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end
            end

            context "when plan has weekly interval" do
              let(:interval) { :weekly }
              let(:from_datetime) { DateTime.parse("2024-02-05T00:00:00") }
              let(:to_datetime) { DateTime.parse("2024-02-11T23:59:59.999") }
              let(:charges_from_datetime) { DateTime.parse("2024-02-05T00:00:00") }
              let(:charges_to_datetime) { DateTime.parse("2024-02-11T23:59:59.999") }
              let(:fixed_charges_from_datetime) { DateTime.parse("2024-02-05T00:00:00") }
              let(:fixed_charges_to_datetime) { DateTime.parse("2024-02-11T23:59:59.999") }
              let(:timestamp) { DateTime.parse("2024-02-12T10:00:00") }

              context "when fees total amount is greater or equal than the commitment amount" do
                it "returns result with zero amount cents" do
                  expect(service_call.amount_cents).to eq(0)
                end
              end

              context "when fees total amount is smaller than the commitment amount" do
                let(:commitment_amount_cents) { 10_000 }

                context "with an in-advance charge for the next period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime: DateTime.parse("2024-02-12T00:00:00"),
                        charges_to_datetime: DateTime.parse("2024-02-18T23:59:59.999")
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance charge for current period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500,
                      properties: {
                        charges_from_datetime:,
                        charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_000)
                  end
                end

                context "with an in-advance charge from another period" do
                  before do
                    create(
                      :charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      charge: create(:standard_charge, :pay_in_advance),
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for the next period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime: DateTime.parse("2024-02-12T00:00:00"),
                        fixed_charges_to_datetime: DateTime.parse("2024-02-18T23:59:59.999")
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge for current period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500,
                      properties: {
                        fixed_charges_from_datetime:,
                        fixed_charges_to_datetime:
                      }
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(8_850)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end

                context "with an in-advance fixed charge from another period" do
                  before do
                    create(
                      :fixed_charge_fee,
                      invoice: nil,
                      subscription:,
                      pay_in_advance: true,
                      fixed_charge: fixed_charge_pay_in_advance,
                      amount_cents: 500
                    )
                  end

                  it "returns result with amount cents" do
                    # TODO: include fixed charge in min commitment calculations
                    # expect(service_call.amount_cents).to eq(9_350)
                    expect(service_call.amount_cents).to eq(9_500)
                  end
                end
              end
            end
          end
        end
      end
    end

    context "when plan is paid in advance" do
      let(:pay_in_advance) { true }

      context "when plan has no minimum commitment" do
        it "returns result with zero amount cents" do
          expect(service_call.amount_cents).to eq(0)
        end
      end

      context "when plan has minimum commitment" do
        let(:commitment) { create(:commitment, plan:, amount_cents: commitment_amount_cents) }
        let(:commitment_amount_cents) { 3_000 }

        before { commitment }

        context "when there are subscription fees" do
          before do
            create(
              :fee,
              subscription: invoice_subscription.subscription,
              invoice: invoice_subscription.invoice,
              properties: {
                from_datetime: DateTime.parse("2024-01-02T00:00:00"),
                to_datetime: DateTime.parse("2024-01-07T23:59:59.999")
              },
              amount_cents: 857 # prorated
            )
          end

          context "when subscription is calendar" do
            let(:billing_time) { :calendar }

            context "when plan has weekly interval" do
              let(:interval) { :weekly }

              context "when fees total amount is smaller than the commitment amount" do
                let(:commitment_amount_cents) { 3_000 }

                context "with an in-advance charge from the period" do
                  context "with no previous period" do
                    let(:from_datetime) { DateTime.parse("2024-01-02T00:00:00") }
                    let(:to_datetime) { DateTime.parse("2024-01-07T23:59:59.999") }
                    let(:charges_from_datetime) { DateTime.parse("2024-01-02T00:00:00") }
                    let(:charges_to_datetime) { DateTime.parse("2024-01-07T23:59:59.999") }
                    let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-02T00:00:00") }
                    let(:fixed_charges_to_datetime) { DateTime.parse("2024-01-07T23:59:59.999") }
                    let(:timestamp) { DateTime.parse("2024-02-02T10:00:00") }

                    before do
                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 700,
                        properties: {
                          charges_from_datetime: invoice_subscription.charges_from_datetime,
                          charges_to_datetime: invoice_subscription.charges_to_datetime
                        }
                      )

                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: false,
                        charge: create(:standard_charge),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: invoice_subscription.charges_from_datetime,
                          charges_to_datetime: invoice_subscription.charges_to_datetime
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      expect(service_call.amount_cents).to eq(0)
                    end
                  end

                  context "with previous period" do
                    let(:previous_invoice_subscription) do
                      create(
                        :invoice_subscription,
                        subscription:,
                        from_datetime: DateTime.parse("2024-01-02T00:00:00"),
                        to_datetime: DateTime.parse("2024-01-07T23:59:59.999"),
                        charges_from_datetime: DateTime.parse("2024-01-02T00:00:00"),
                        charges_to_datetime: DateTime.parse("2024-01-07T23:59:59.999"),
                        fixed_charges_from_datetime: DateTime.parse("2024-01-02T00:00:00"),
                        fixed_charges_to_datetime: DateTime.parse("2024-01-07T23:59:59.999"),
                        timestamp: DateTime.parse("2024-01-02T10:00:00")
                      )
                    end

                    let(:from_datetime) { DateTime.parse("2024-01-08T00:00:00") }
                    let(:to_datetime) { DateTime.parse("2024-01-14T23:59:59.999") }
                    let(:charges_from_datetime) { DateTime.parse("2024-01-08T00:00:00") }
                    let(:charges_to_datetime) { DateTime.parse("2024-01-14T23:59:59.999") }
                    let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-08T00:00:00") }
                    let(:fixed_charges_to_datetime) { DateTime.parse("2024-01-14T23:59:59.999") }
                    let(:timestamp) { DateTime.parse("2024-02-08T10:00:00") }

                    before do
                      create(
                        :fee,
                        subscription: previous_invoice_subscription.subscription,
                        invoice: previous_invoice_subscription.invoice
                      )

                      create(
                        :charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        charge: create(:standard_charge, :pay_in_advance),
                        amount_cents: 700,
                        properties: {
                          charges_from_datetime: previous_invoice_subscription.charges_from_datetime,
                          charges_to_datetime: previous_invoice_subscription.charges_to_datetime
                        }
                      )

                      create(
                        :charge_fee,
                        invoice: invoice_subscription.invoice,
                        subscription:,
                        pay_in_advance: false,
                        charge: create(:standard_charge),
                        amount_cents: 500,
                        properties: {
                          charges_from_datetime: previous_invoice_subscription.charges_from_datetime,
                          charges_to_datetime: previous_invoice_subscription.charges_to_datetime
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      expect(service_call.amount_cents).to eq(514)
                    end
                  end
                end

                context "with an in-advance fixed charge from the period" do
                  context "with no previous period" do
                    let(:from_datetime) { DateTime.parse("2024-01-02T00:00:00") }
                    let(:to_datetime) { DateTime.parse("2024-01-07T23:59:59.999") }
                    let(:charges_from_datetime) { DateTime.parse("2024-01-02T00:00:00") }
                    let(:charges_to_datetime) { DateTime.parse("2024-01-07T23:59:59.999") }
                    let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-02T00:00:00") }
                    let(:fixed_charges_to_datetime) { DateTime.parse("2024-01-07T23:59:59.999") }
                    let(:timestamp) { DateTime.parse("2024-02-02T10:00:00") }

                    before do
                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 700,
                        properties: {
                          fixed_charges_from_datetime: invoice_subscription.fixed_charges_from_datetime,
                          fixed_charges_to_datetime: invoice_subscription.fixed_charges_to_datetime
                        }
                      )

                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: false,
                        fixed_charge: fixed_charge,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: invoice_subscription.fixed_charges_from_datetime,
                          fixed_charges_to_datetime: invoice_subscription.fixed_charges_to_datetime
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      expect(service_call.amount_cents).to eq(0)
                    end
                  end

                  context "with previous period" do
                    let(:previous_invoice_subscription) do
                      create(
                        :invoice_subscription,
                        subscription:,
                        from_datetime: DateTime.parse("2024-01-02T00:00:00"),
                        to_datetime: DateTime.parse("2024-01-07T23:59:59.999"),
                        charges_from_datetime: DateTime.parse("2024-01-02T00:00:00"),
                        charges_to_datetime: DateTime.parse("2024-01-07T23:59:59.999"),
                        fixed_charges_from_datetime: DateTime.parse("2024-01-02T00:00:00"),
                        fixed_charges_to_datetime: DateTime.parse("2024-01-07T23:59:59.999"),
                        timestamp: DateTime.parse("2024-01-02T10:00:00")
                      )
                    end

                    let(:from_datetime) { DateTime.parse("2024-01-08T00:00:00") }
                    let(:to_datetime) { DateTime.parse("2024-01-14T23:59:59.999") }
                    let(:charges_from_datetime) { DateTime.parse("2024-01-08T00:00:00") }
                    let(:charges_to_datetime) { DateTime.parse("2024-01-14T23:59:59.999") }
                    let(:fixed_charges_from_datetime) { DateTime.parse("2024-01-08T00:00:00") }
                    let(:fixed_charges_to_datetime) { DateTime.parse("2024-01-14T23:59:59.999") }
                    let(:timestamp) { DateTime.parse("2024-02-08T10:00:00") }

                    before do
                      create(
                        :fee,
                        subscription: previous_invoice_subscription.subscription,
                        invoice: previous_invoice_subscription.invoice
                      )

                      create(
                        :fixed_charge_fee,
                        invoice: nil,
                        subscription:,
                        pay_in_advance: true,
                        fixed_charge: fixed_charge_pay_in_advance,
                        amount_cents: 700,
                        properties: {
                          fixed_charges_from_datetime: previous_invoice_subscription.fixed_charges_from_datetime,
                          fixed_charges_to_datetime: previous_invoice_subscription.fixed_charges_to_datetime
                        }
                      )

                      create(
                        :fixed_charge_fee,
                        invoice: invoice_subscription.invoice,
                        subscription:,
                        pay_in_advance: false,
                        fixed_charge: fixed_charge,
                        amount_cents: 500,
                        properties: {
                          fixed_charges_from_datetime: previous_invoice_subscription.fixed_charges_from_datetime,
                          fixed_charges_to_datetime: previous_invoice_subscription.fixed_charges_to_datetime
                        }
                      )
                    end

                    it "returns result with amount cents" do
                      # TODO: include fixed charge in min commitment calculations
                      # expect(service_call.amount_cents).to eq(514)
                      expect(service_call.amount_cents).to eq(1_714)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end
