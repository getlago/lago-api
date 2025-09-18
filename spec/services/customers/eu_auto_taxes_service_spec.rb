# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::EuAutoTaxesService do
  subject(:eu_tax_service) { described_class.new(customer:, new_record:, tax_attributes_changed:) }

  let(:organization) { create(:organization, country: "IT", eu_tax_management: true) }
  let(:billing_entity) { create(:billing_entity, organization:, country: "FR", eu_tax_management: true) }
  let(:customer) { create(:customer, organization:, billing_entity:, tax_identification_number:, zipcode: nil) }
  let(:new_record) { true }
  let(:tax_attributes_changed) { true }
  let(:tax_identification_number) { "IT12345678901" }

  describe ".call" do
    before do
      allow_any_instance_of(Valvat).to receive(:exists?).and_return(vies_response) # rubocop:disable RSpec/AnyInstance
    end

    context "with B2B organization" do
      let(:vies_response) { {} }

      context "when tax_identification_number is blank" do
        let(:tax_identification_number) { nil }

        before { customer.update!(country: "DE") }

        it "returns the default tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
          expect(SendWebhookJob).not_to have_been_enqueued
        end
      end

      context "when vat number is invalid" do
        let(:tax_identification_number) { "invalid_vat_number" }

        before do
          # No call to the API is made when the format is invalid
          allow_any_instance_of(Valvat).to receive(:exists?).and_call_original # rubocop:disable RSpec/AnyInstance
          customer.update!(country: "DE")
        end

        it "returns the default tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
          expect(SendWebhookJob).to have_been_enqueued.with("customer.vies_check", customer, vies_check: {
            valid: false,
            valid_format: false
          }).once
        end
      end

      context "when VIES check raises an error" do
        before do
          allow_any_instance_of(Valvat).to receive(:exists?) # rubocop:disable RSpec/AnyInstance
            .and_raise(Valvat::RateLimitError.new("rate limit reached", nil))
          customer.update!(country: "DE")
        end

        it "returns the default tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
          expect(SendWebhookJob).to have_been_enqueued.with("customer.vies_check", customer, vies_check: {
            valid: false,
            valid_format: true,
            error: "The  web service returned the error: rate limit reached"
          }).once
        end
      end

      context "when VIES check raises MemberStateUnavailable error" do
        before do
          allow_any_instance_of(Valvat).to receive(:exists?) # rubocop:disable RSpec/AnyInstance
            .and_raise(Valvat::MemberStateUnavailable.new("member state unavailable", nil))
          customer.update!(country: "DE")
        end

        it "returns the default tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
          expect(SendWebhookJob).to have_been_enqueued.with("customer.vies_check", customer, vies_check: {
            valid: false,
            valid_format: true,
            error: "The  web service returned the error: member state unavailable"
          }).once
        end

        it "enqueues RetryViesCheckJob" do
          eu_tax_service.call

          expect(Customers::RetryViesCheckJob).to have_been_enqueued.at(4.minutes.from_now..6.minutes.from_now).with(customer.id).once
        end
      end

      context "when VIES check raises ServiceUnavailable error" do
        before do
          allow_any_instance_of(Valvat).to receive(:exists?) # rubocop:disable RSpec/AnyInstance
            .and_raise(Valvat::ServiceUnavailable.new("service unavailable", nil))
          customer.update!(country: "DE")
        end

        it "returns the default tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
          expect(SendWebhookJob).to have_been_enqueued.with("customer.vies_check", customer, vies_check: {
            valid: false,
            valid_format: true,
            error: "The  web service returned the error: service unavailable"
          }).once
        end

        it "enqueues RetryViesCheckJob" do
          eu_tax_service.call

          expect(Customers::RetryViesCheckJob).to have_been_enqueued.at(4.minutes.from_now..6.minutes.from_now).with(customer.id).once
        end
      end

      context "when eu_tax_management is false" do
        let(:organization) { create(:organization, country: "IT", eu_tax_management: false) }
        let(:billing_entity) { create(:billing_entity, organization:, country: "FR", eu_tax_management: false) }

        it "returns error" do
          result = eu_tax_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("eu_tax_not_applicable")
        end
      end

      context "when customer is updated and there are eu taxes" do
        let(:new_record) { false }
        let(:tax_attributes_changed) { false }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: "lago_eu_tax_exempt") }

        before { applied_tax }

        it "returns error" do
          result = eu_tax_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("eu_tax_not_applicable")
        end
      end

      context "when customer is updated and there are no eu taxes" do
        let(:new_record) { false }
        let(:tax_attributes_changed) { false }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: "unknown_eu_tax_exempt") }
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        before { applied_tax }

        it "returns the billing_entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end
      end

      context "with same country as the billing_entity" do
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        it "returns the organization country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end

        it "enqueues a SendWebhookJob" do
          eu_tax_service.call

          expect(SendWebhookJob).to have_been_enqueued
            .with("customer.vies_check", customer, vies_check: vies_response)
            .once
        end
      end

      context "with a different country from the billing_entity one" do
        let(:vies_response) do
          {
            country_code: "DE"
          }
        end

        it "returns the reverse charge tax" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_reverse_charge")
        end
      end

      context "when country has exceptions" do
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        context "when customer has no zipcode" do
          it "returns the customer country standard tax" do
            result = eu_tax_service.call
            expect(result.tax_code).to eq("lago_eu_fr_standard")
          end
        end

        context "when customer has a zipcode" do
          context "when zipcode has applicable exceptions" do
            before do
              customer.update(zipcode: "97412")
            end

            it "returns the exception tax code" do
              result = eu_tax_service.call
              expect(result.tax_code).to eq("lago_eu_fr_exception_reunion")
            end
          end

          context "when zipcode has no applicable exceptions" do
            before do
              customer.update(zipcode: "12345")
            end

            it "returns the customer counrty standard tax" do
              result = eu_tax_service.call
              expect(result.tax_code).to eq("lago_eu_fr_standard")
            end
          end
        end
      end
    end

    context "with non B2B" do
      let(:vies_response) { false }

      context "when the customer has no country" do
        before do
          customer.update(country: nil)
        end

        it "returns the billing entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end
      end

      context "when the customer country is in europe" do
        before do
          customer.update(country: "DE")
        end

        it "returns the customer country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_de_standard")
        end
      end

      context "when the customer country is out of europe" do
        before do
          customer.update(country: "US")
        end

        it "returns the tax exempt tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_tax_exempt")
        end
      end
    end
  end
end
