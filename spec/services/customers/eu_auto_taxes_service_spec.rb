# frozen_string_literal: true

require "rails_helper"
require "valvat"

RSpec.describe Customers::EuAutoTaxesService, type: :service do
  subject(:eu_tax_service) { described_class.new(customer:) }

  let(:organization) { create(:organization, country: "FR") }
  let(:customer) { create(:customer, organization:) }

  describe ".call" do
    context "with B2B organization" do
      let(:vies_service) { instance_double(Valvat) }

      before do
        allow(Valvat).to receive(:new).and_return(vies_service)
        allow(vies_service).to receive(:exists?).and_return(vies_response)
      end

      context "with same country as the organization" do
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        it "returns the organization country tax code" do
          tax_code = eu_tax_service.call

          expect(tax_code).to eq("lago_eu_fr_standard")
        end

        it "enqueues a SendWebhookJob" do
          eu_tax_service.call

          expect(SendWebhookJob).to have_been_enqueued
            .with("customer.vies_check", customer, vies_check: vies_response)
        end
      end

      context "with a different country from the organization one" do
        let(:vies_response) do
          {
            country_code: "DE"
          }
        end

        it "returns the reverse charge tax" do
          tax_code = eu_tax_service.call

          expect(tax_code).to eq("lago_eu_reverse_charge")
        end
      end
    end

    context "with non B2B" do
      let(:vies_response) { false }

      context "when the customer has no country" do
        before do
          customer.update(country: nil)
        end

        it "returns the organization country tax code" do
          tax_code = eu_tax_service.call

          expect(tax_code).to eq("lago_eu_fr_standard")
        end
      end

      context "when the customer country is in europe" do
        before do
          customer.update(country: "DE")
        end

        it "returns the customer country tax code" do
          tax_code = eu_tax_service.call

          expect(tax_code).to eq("lago_eu_de_standard")
        end
      end

      context "when the customer country is out of europe" do
        before do
          customer.update(country: "US")
        end

        it "returns the tax exempt tax code" do
          tax_code = eu_tax_service.call

          expect(tax_code).to eq("lago_eu_tax_exempt")
        end
      end
    end
  end
end
