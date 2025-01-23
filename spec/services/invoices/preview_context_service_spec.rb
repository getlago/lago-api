# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Invoices::PreviewContextService, type: :service do
  let(:result) { described_class.call(organization:, params:) }

  describe "#call" do
    let(:organization) { create(:organization) }
    let(:plan) { create(:plan, organization:) }
    let(:customer) { create(:customer, organization:) }

    let(:params) do
      {
        customer: {external_id: customer.external_id},
        plan_code: plan.code,
        coupons: []
      }
    end

    before do
      create(:coupon, organization:) { |coupon| customer.coupons << coupon }
    end

    it "assigns customer, plan, and applied coupons to result" do
      expect(result)
        .to be_success
        .and have_attributes(customer:, subscription: Subscription, applied_coupons: customer.applied_coupons)
    end
  end

  describe "#customer" do
    subject { result.customer }

    let(:organization) { create(:organization) }

    before { create(:customer, organization:) }

    context "when customer external id is provided" do
      let(:params) do
        {
          customer: {external_id:}
        }
      end

      context "when customer matching external id exists in organization" do
        let(:customer) { create(:customer, organization:) }
        let(:external_id) { customer.external_id }

        it "returns customer" do
          expect(subject).to eq customer
        end
      end

      context "when customer matching external id does not exist in organization" do
        let(:external_id) { SecureRandom.uuid }

        it "returns nil" do
          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.error_code).to eq("customer_not_found")

          expect(subject).to be_nil
        end
      end
    end

    context "when customer external id is omitted" do
      let(:params) do
        {
          customer: {
            name: "Mislav M",
            tax_identification_number: "123",
            currency: "EUR",
            shipping_address: {
              address_line1: "Rue de Tax",
              address_line2: nil,
              state: nil,
              city: "Paris",
              zipcode: "75011",
              country: "IT"
            },
            integration_customers:
          }
        }
      end

      context "when integration customers params passed" do
        let(:integration_customers) do
          [
            {
              integration_type: "anrok",
              integration_code: "code"
            }
          ]
        end

        context "when integration matching params exists" do
          let(:expected_attributes) do
            params[:customer].tap do |hash|
              hash[:integration_customers] = [IntegrationCustomers::AnrokCustomer]
            end
          end

          before { create(:anrok_integration, organization:, code: "code") }

          it "returns new customer build from params including integration customers" do
            expect(subject)
              .to be_present
              .and be_new_record
              .and have_attributes(expected_attributes)
          end
        end

        context "when integration matching params does not exist" do
          it "returns nil" do
            expect(result).not_to be_success
            expect(result.error).to be_a(BaseService::NotFoundFailure)
            expect(result.error.error_code).to eq("anrok_integration_not_found")

            expect(subject).to be_nil
          end
        end
      end

      context "when integration customers params is omitted or empty" do
        let(:integration_customers) { [] }
        let(:expected_attributes) { params[:customer] }

        it "returns new customer build from params" do
          expect(subject)
            .to be_present
            .and be_new_record
            .and have_attributes(expected_attributes)
        end
      end
    end
  end

  describe "#subscription" do
    subject { result.subscription }

    let(:organization) { customer.organization }
    let(:customer) { create(:customer) }

    let(:params) do
      {
        customer: {external_id: customer.external_id},
        plan_code: plan&.code,
        subscription_at: subscription_at&.iso8601,
        billing_time:
      }
    end

    context "when plan matching provided code exists" do
      let(:plan) { create(:plan, organization:) }

      before { freeze_time }

      context "when billing time and subscription date are present" do
        let(:subscription_at) { generate(:past_date) }
        let(:billing_time) { 'anniversary' }

        it "returns new subscription with provided params" do
          expect(subject)
            .to be_a(Subscription)
            .and have_attributes(
              customer:,
              plan:,
              subscription_at: subscription_at,
              started_at: subscription_at,
              billing_time: params[:billing_time]
            )
        end
      end

      context "when billing time and subscription date are missing" do
        let(:subscription_at) { nil }
        let(:billing_time) { nil }

        it "returns new subscription with default values for subscription date and billing time" do
          expect(subject)
            .to be_a(Subscription)
            .and have_attributes(
              customer:,
              plan:,
              subscription_at: Time.current,
              started_at: Time.current,
              billing_time: 'calendar'
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

  describe "#applied_coupons" do
    subject { result.applied_coupons }

    let(:organization) { create(:organization) }
    let(:plan) { create(:plan, organization:) }

    let(:params) do
      {
        customer: customer_params,
        plan_code: plan.code,
        coupons: coupon_params
      }
    end

    context "when customer has applied coupons" do
      let(:customer_params) { {external_id: customer.external_id} }
      let(:customer) { create(:customer, organization:) }

      before do
        create(:coupon, organization:) { |coupon| customer.coupons << coupon }
      end

      context "when coupons are provided" do
        let(:coupon_params) do
          [
            {
              code: coupon.code
            },
            {
              code: "coupon_preview",
              name: "coupon_preview",
              coupon_type: "percentage",
              amount_cents: 1200,
              amount_currency: "EUR",
              percentage_rate: 1
            }
          ]
        end

        let(:coupon) { create(:coupon, organization:) }

        it "returns customer's applied coupons" do
          expect(subject).to be_present.and eq customer.applied_coupons
        end
      end

      context "when coupons are empty" do
        let(:coupon_params) { [] }

        it "returns customer's applied coupons" do
          expect(subject).to be_present.and eq customer.applied_coupons
        end
      end
    end

    context "when customer has no applied coupons" do
      let(:customer_params) { {name: Faker::Name.name} }

      context "when coupons are provided" do
        let(:coupon_params) do
          [
            {
              code: coupon.code
            },
            {
              code: "coupon_preview",
              name: "coupon_preview",
              coupon_type: "percentage",
              amount_cents: 1200,
              amount_currency: "EUR",
              percentage_rate: 1
            }
          ]
        end

        let(:coupon) { create(:coupon, organization:) }

        it "returns applied coupons build from provided params" do
          expect(subject).to be_a(Array).and match_array([AppliedCoupon, AppliedCoupon])

          expect(subject.map { |ac| ac.coupon.code })
            .to match_array coupon_params.map { |i| i[:code] }
        end
      end

      context "when coupons are empty" do
        let(:coupon_params) { [] }

        it "returns empty collection" do
          expect(subject).to be_empty
        end
      end
    end
  end
end
